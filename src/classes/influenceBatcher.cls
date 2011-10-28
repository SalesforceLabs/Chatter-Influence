// Jonathan Hersh - jhersh@salesforce.com - Dec '10
// Creates and executes batch Apex jobs to calculate Chatter Influence

/* CODECAT IS NOT AMUSED
* /\_/| 
* =0-0=
* \'I'|
* |<|,,\_
* |[>,,/,\ 
* |[|,\_,,)
* ((J(=__/
*/

public with sharing class influenceBatcher {
    public Influence_Parent__c ip           { get; set; }
    public integer MAX_SYSTEM_JOBS          { get { return 5; } }
    
    public integer MAX_JOBS                 { get { 
        if( ip.maximum_concurrent_batches__c != null )
            return ip.maximum_concurrent_batches__c.intvalue();
        return 5;
    } }
    
    public integer currentJobs              { get; set; }
    public Map<integer,string[]> sortRanks  { get; set; }
    public string[] sObs                    { get; set; }
    public string statusmsg                 { get; set; }
    public boolean isTest                   { get; set; } { isTest = false; }
    
    public static Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
    
    public influenceBatcher( ApexPages.standardcontroller c ) {
        ip = [select id, total_jobs__c, status__c, jobs_executed__c, include_custom_object_feeds__c, lastmodifieddate, maximum_concurrent_batches__c, records_to_exclude__c
            from Influence_Parent__c 
            where id = :c.getId() ];
        
        if( ip.status__c == null || ip.status__c == '' || ip.status__c == 'Ready' ) {
            statusmsg = 'Ready to calculate Chatter Influence. Total duration will depend on the amount of Chatter data in your environment as well as the time period you select.';
            ip.status__c = 'Ready';
        } else if( ip.status__c == 'Complete' )
            statusmsg = 'Calculation complete. Create a new Influence Snapshot record if you\'d like to re-calculate the data.';
        
        sObs = new string[] {};
        
        // Calculate post and comment data from all Chatter-enabled objects
        for( string s : gd.keySet() ) {
            Schema.Sobjecttype ob = gd.get( s );
            Schema.Describesobjectresult sob = ob.getDescribe();
            
            if( sob.getKeyPrefix() == null || sob.getName() == 'EntitySubscription' )
                continue;
                
            if( !sob.isFeedEnabled() )
                continue;
                
            if( sob.isCustom() && !ip.include_custom_object_feeds__c )
                continue;
                
            string name;
            
            if( sob.getName().contains('__ka') )
                name = sob.getName().replace( '__ka', '__Feed' );
            else if( sob.getName().contains('__c') )
                name = sob.getName().replace( '__c', '__Feed' );
            else
                name = sob.getName() + 'Feed';
            
            sObs.add( name );
        }
        
        sObs.sort();
        
        // The entitysubscription batch must go last, as it changes the status on the parent
        sObs.add( 'EntitySubscription' );
        
        // Calculate rankings for each Influence stat   
        sortRanks = new Map<integer,string[]> ();           
        sortRanks.put( 0, new string[] { 'posts_created__c', 'PC_Rank__c', 'Median_Posts_Created__c' } );
        sortRanks.put( 1, new string[] { 'posts_received__c', 'PR_Rank__c', 'Median_Posts_Received__c' } );
        sortRanks.put( 2, new string[] { 'comments_created__c', 'CC_Rank__c', 'Median_Comments_Created__c' } );
        sortRanks.put( 3, new string[] { 'comments_received__c', 'CR_Rank__c', 'Median_Comments_Received__c' } );
        sortRanks.put( 4, new string[] { 'followers__c', 'F_Rank__c', 'Median_Followers__c' } );
        sortRanks.put( 5, new string[] { 'comments_per_day__c', 'ACD_rank__c', 'Median_Day_Comments__c' } );
        sortRanks.put( 6, new string[] { 'likes_received__c', 'likes_received_rank__c', 'Median_Likes_Received__c' } );
        sortRanks.put( 7, new string[] { 'avg_interactions_post__c', 'AIP_rank__c', 'Median_Interactions_Post__c' } );
    }
    
    public pageReference doBatch() {    
        // recalc current jobs and parent status
        ip = [select total_jobs__c, lastmodifieddate, status__c, jobs_executed__c, maximum_concurrent_batches__c, records_to_exclude__c from Influence_Parent__c where id = :ip.id];
                
        // How many other jobs are in progress?
        currentJobs = integer.valueof( [Select count(id) jobs from AsyncApexJob 
            where jobtype = 'BatchApex' 
            and ( status = 'Queued' or status = 'Processing' or status = 'Preparing' ) ].get(0).get('jobs') );
        
        if( ip.status__c == null || ip.status__c == 'Ready' )
            ip.status__c = 'Loading Chatter Data';
        else if( ip.status__c == 'Complete' )
            statusmsg = 'Calculation complete. Refresh the page to see the results!';
        
        integer launched = 0;
        Set<ID> exclude = new Set<ID> ();
        
        // Parse out our exclude list
        if( ip.records_to_exclude__c != null ) {
            if( !ip.records_to_exclude__c.endsWith(',') )
                ip.records_to_exclude__c += ',';
                
            for( string s : ip.records_to_exclude__c.split(',') ) {
                try {
                    ID tmp = ID.valueof( s );
                    
                    exclude.add( tmp );
                } catch( Exception e ) {}
            }
        }
        
        // How many total jobs we will be executing
        ip.total_jobs__c = sObs.size() + sortRanks.size() + 1;
        
        if( currentJobs >= MAX_SYSTEM_JOBS ) 
            return null;
        
        if( ip.status__c == 'Loading Chatter Data' && ip.jobs_executed__c <= sObs.size() ) {
            esBatch eb;
            fpBatch fp;
            string obName;
            integer j = ip.jobs_executed__c.intvalue();
            
            j = ( j == sObs.size() ? j - 1 : j );
            obName = sObs.get( j );
            
            // We only start another data load if there is not currently one executing
            ApexClass[] myClasses = [select id from ApexClass where name = 'esBatch' or name = 'fpBatch'];
            AsyncApexJob[] myjobs = [Select id, jobitemsprocessed, totaljobitems, status from AsyncApexJob 
                    where jobtype = 'BatchApex' 
                    and ( status = 'Queued' or status = 'Processing' or status = 'Preparing' )
                    and apexclassid IN :myClasses
                    order by createddate asc];
                    
            if( !myjobs.isEmpty() ) {
                if( myJobs[0].status == 'Processing' )
                    statusmsg = 'Loaded '+ myjobs[0].jobitemsprocessed +' of '+ myjobs[0].totaljobitems +' batches from '+ obName +'.';
                else if( myJobs[0].status == 'Queued' )
                    statusmsg = 'Waiting for queued '+ obName +' data load to begin.';
                else
                    statusmsg = 'Preparing '+ obName +' data load.';
            } else {
                statusmsg = 'Loading Chatter data from '+ obName +'...';
                launched++;
                    
                if( obName == 'EntitySubscription' ) {
                    eb = new esBatch();
                    eb.exclude = exclude;
                    eb.ipID = ip.id;
                    eb.isTest = isTest;
                    Database.executeBatch(eb);
                } else {
                    fp = new fpBatch();
                    fp.ipID = ip.id;
                    fp.exclude = exclude;
                    fp.objectType = obName;
                    fp.isTest = isTest;
                    Database.executeBatch(fp);
                }
            }
        } else if( ip.status__c == 'Sorting Data' && ip.jobs_executed__c < sObs.size() + sortRanks.size() ) {   
            statusmsg = 'Sorting data and calculating rankings.';
            integer c = MAX_SYSTEM_JOBS - currentJobs;
            
            if( c > MAX_JOBS ) c = MAX_JOBS;
                                
            for( integer i = 0; i < c; i++ ) {
                integer j = ip.jobs_executed__c.intvalue() - sObs.size();
                
                if( j + launched >= sortRanks.size() )
                    continue;
                
                j += launched;
                
                if( sortRanks.get(j) == null )
                    continue;
                                    
                launched++;
                                            
                string key = sortRanks.get(j)[0];
                string val = sortRanks.get(j)[1];
                string med = sortRanks.get(j)[2];
                
                orderingBatch ob = new orderingBatch();
                ob.ipID = ip.id;
                
                ob.doUpdateParent = j == sortRanks.size() - 1;     
                ob.sortField = key;
                ob.rankField = val;
                ob.medianField = med;
                
                Database.executeBatch(ob);              
            }
        } else if( ip.status__c == 'Finalizing Influence' && ip.jobs_executed__c < sObs.size() + sortRanks.size() + 1 ) {
            statusmsg = 'Just a little bit longer!';
            
            if( MAX_SYSTEM_JOBS - currentJobs > 0 ) {
                // Final job - sort everyone by influence scores
                orderingBatch ob = new orderingBatch();
                ob.ipID = ip.id;
                    
                ob.doUpdateParent = true;               
                ob.sortField = 'influence_formula__c';
                ob.rankField = 'ranking__c';
                ob.medianField = 'Median_Influence__c';
                    
                Database.executeBatch(ob);
                
                launched = 1;
            }
        }
        
        // Update the parent with the number of jobs we launched this time
        if( launched > 0 )
            ip.jobs_executed__c += launched;
        
        try {
            update ip;
        } catch( Exception e ) {}
        
        return null;
    }
    
    public static string soqlDate( datetime d ) {
        return d.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }
    
    public static testmethod void runTest() {
        // New Inf parent
        Influence_Parent__c ip = new Influence_Parent__c( active__c = true, start_time__c = datetime.now().addMonths(-6), end_time__c = datetime.now(), maximum_concurrent_batches__c = 5, status__c = 'Ready' );
        insert ip;
        
        Apexpages.standardcontroller c = new apexpages.Standardcontroller( ip );
        
        influenceBatcher ib = new influenceBatcher( c );
        ib.isTest = true;
        
        Test.startTest();
        ib.doBatch();
        Test.stopTest();
    }
    
    public static testmethod void runTestES() {
        // New Inf parent
        Influence_Parent__c ip = new Influence_Parent__c( active__c = true, start_time__c = datetime.now().addMonths(-6), end_time__c = datetime.now(), maximum_concurrent_batches__c = 5, status__c = 'Ready', records_to_exclude__c = userinfo.getuserid() );
        insert ip;
        
        Apexpages.standardcontroller c = new apexpages.Standardcontroller( ip );
        
        influenceBatcher ib = new influenceBatcher( c );
        ib.isTest = true;
        ip.jobs_executed__c = ib.sObs.size() - 1;
        
        update ip;
        
        Test.startTest();
        ib.doBatch();
        Test.stopTest();
    }
    
    public static testmethod void runTest2() {      
        // New Inf parent
        Influence_Parent__c ip = new Influence_Parent__c( active__c = true, start_time__c = datetime.now().addMonths(-6), end_time__c = datetime.now(), maximum_concurrent_batches__c = 5, status__c = 'Ready' );
        ip.status__c = 'Sorting Data';
        
        insert ip;
        
        Apexpages.standardcontroller c = new apexpages.Standardcontroller( ip );
        influenceBatcher ib = new influenceBatcher( c );
        ib.isTest = true;
        
        ip.jobs_executed__c = ib.sObs.size();
        update ip;
        
        Test.startTest();
        ib.doBatch();
        Test.stopTest();
    }
    
    public static testmethod void runTest3() {
        // New Inf parent
        Influence_Parent__c ip = new Influence_Parent__c( active__c = true, start_time__c = datetime.now().addMonths(-6), end_time__c = datetime.now(), maximum_concurrent_batches__c = 5, status__c = 'Ready' );

        ip.status__c = 'Finalizing Influence';
        
        insert ip;
        
        Apexpages.standardcontroller c = new apexpages.Standardcontroller( ip );
        influenceBatcher ib = new influenceBatcher( c );
        ib.isTest = true;
        
        ip.jobs_executed__c = ib.sObs.size() + ib.sortRanks.size();
        update ip;
        
        Test.startTest();
        ib.doBatch();
        Test.stopTest();
    }
}