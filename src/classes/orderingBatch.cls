// Jonathan Hersh - jhersh@salesforce.com - 12/2010
// Ordering batch calculator

global class orderingBatch implements Database.Batchable<sObject>, Database.Stateful {

    global String ipID;
    global Influence_Parent__c ip   { get; set; }
    global integer pos { get; set; }
    global integer curTotal { get; set; }
    global decimal totalInf { get; set; }
    global decimal median   { get; set; }
    global string sortField;
    global string rankField;
    global string medianField;
    global boolean doUpdateParent;

    global Database.QueryLocator start(Database.BatchableContext BC){        
        pos = 1;
        curTotal = 0;
        totalInf = 0.0;
        median = 0.0;
        
        try {
            ip = [select id, jobs_executed__c, total_records__c, status__c from Influence_Parent__c where id = :ipID];
        } catch( Exception e ) {
            return null;
        }
        
        return Database.getQueryLocator('select id, '+ rankField +', '+ sortField +' '+
            ' from Influence__c '+
            ' where influence_parent__c = :ipID '+
            ' order by '+ sortField +' desc');
    }

    global void execute(Database.BatchableContext BC, List<sObject> scope){
        // Try to recover if something really wrong happens
        try {
            ip = [select id, jobs_executed__c, total_records__c, status__c from Influence_Parent__c where id = :ipID];
        } catch( Exception e ) {
            return;
        }
        
        for( integer j = 0; j < scope.size(); j++ ) { 
            integer i = j > 0 ? j - 1 : j;  
            decimal prev, cur;
            
            curTotal++;
            
            if( scope[i].get( sortField ) == null )
                prev = 0;
            else {
                try {
                    prev = decimal.valueof( double.valueof( scope[i].get( sortField ) ) );
                } catch( TypeException te ) {
                    prev = decimal.valueof( string.valueof( scope[i].get( sortField ) ) );
                }
            }
            
            if( scope[j].get( sortField ) == null )
                cur = 0;
            else {
                try {
                    cur = decimal.valueof( double.valueof( scope[j].get( sortField ) ) );
                } catch( TypeException te ) {
                    cur = decimal.valueof( string.valueof( scope[j].get( sortField ) ) );
                }
            }
                        
            if( cur < prev )
                pos = curTotal;
                
            // If we're sorting influence, add it to our total
            if( rankField.contains('ranking__c') )
                totalInf += cur;
                
            // Are we at the median?
            if( ip.total_records__c > 2 && curTotal == Math.ceil( ip.total_records__c / 2 ) )
                median = cur;
                            
            scope[j].put( rankField, pos );
        }
        
        update scope;
    }

    global void finish(Database.BatchableContext BC) {                  
        try {
            ip = Database.query('select id, influence_sum__c, status__c, '+ medianField +' from Influence_Parent__c where id = :ipID');
        } catch( Exception e ) {
            return;
        }
        
        try {
            ip.put( medianField, median );
        } catch( Exception e ) {}
            
        if( doUpdateParent )
        {
            if( ip.status__c == 'Sorting Data' )
                ip.status__c = 'Finalizing Influence';
            else if( ip.status__c == 'Finalizing Influence' )
                ip.status__c = 'Complete';
        }
            
        if( totalInf > 0 )
            ip.influence_sum__c = totalInf;
        
        try {
            update ip;   
        } catch( Exception e ) {} 
    }
    
    global static testmethod void testOrdering() {      
        // New Inf parent
        Influence_Parent__c ip = new Influence_Parent__c( active__c = true, start_time__c = datetime.now().addMonths(-6), end_time__c = datetime.now(), status__c = 'Sorting Data',  maximum_concurrent_batches__c = 5 );
        insert ip;
        
        // New inf
        Influence__c inf = new Influence__c( influence_parent__c = ip.id, user__c = userinfo.getuserid(), comments_created__c = 1, cc_rank__c = 0 );
        insert inf;
        
        // New user for us to follow
        Profile p = [select id from Profile where usertype='Standard' limit 1];
        User u = new User(alias = 'standt', email='standarduser@kwutang.demo', 
                        emailencodingkey='UTF-8', lastname='Testing1', firstname='Testing', languagelocalekey='en_US', 
                        localesidkey='en_US', profileid = p.Id, 
                        timezonesidkey='America/Los_Angeles', username='standarduser@kwutang.demo');        
        
        try {
            insert u;
            insert new Influence__c( influence_parent__c = ip.id, user__c = u.id, comments_created__c = 2, cc_rank__c = 0 );
        } catch( Exception e ) {
            return;
        }
        
        orderingBatch ob = new orderingBatch();
        ob.ipID = ip.id;
        ob.doUpdateParent = true;
        ob.sortField = 'comments_created__c';
        ob.rankField = 'cc_rank__c';
        ob.medianField = 'median_comments_created__c';

        Test.StartTest();
        ID batchprocessid = Database.executeBatch(ob);
        Test.StopTest();
    
        //System.assertEquals( 2, [select cc_rank__c from Influence__c where influence_parent__c = :ip.id and user__c = :userinfo.getuserid()].cc_rank__c ); 
    }
}