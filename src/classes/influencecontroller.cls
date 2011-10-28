// Jonathan Hersh - jhersh@salesforce.com - Dec '10
public with sharing class influencecontroller {
    public Influence__c[] myInf             { get; set; }
    public Influence_Tracker__c infTracker  { get; set; }
    public boolean submitted                { get; set; }
    public string mess                      { get; set; }
    
    // Leaderboard browsing
    public boolean isTest                   { get; set; }
    public Influence__c[] rankings          { get; set; }
    public string ipID                      { get; set; }
    public Influence_Parent__c ip           { get; set; }
    public string dept                      { get; set; }
    
    public class InfluenceException extends Exception {}
    
    public string updated                   { get { 
            string ret;
            Influence_Parent__c latest;
            
            try {
                latest = [select id, createddate, start_time__c, end_time__c from Influence_Parent__c where active__c = true and start_time__c <> null and end_time__c <> null order by createddate desc limit 1];
            } catch( Exception e ) {
                return '';
            }
            
            ret = 'This Influence report includes Chatter data'; 
                
            ret += ' from '+ latest.start_time__c.format('MMM-dd-yyyy h:mm a ', 'PST') +
                ' to '+ latest.end_time__c.format('MMM-dd-yyyy h:mm a ', 'PST') +'.<br/>';

            return ret;
        } }
    
    public influencecontroller() {
        submitted = false;
        mess = '';
        isTest = false;
        ipID = '';
        dept = '';
        rankings = new Influence__c[] {};
    }
    
    public void sendInfluence() {        
        User u = [select id, email from User where id = :userinfo.getuserid()];
        submitted = true;
        mess = '';
        
        // Get the most recent influence parent for each selected environment
        Influence_Parent__c parent;
            
            try {
                parent = [select id, track_influence_reports__c from Influence_Parent__c where active__c = true order by createddate desc limit 1];
            } catch( Exception e ) {
                parent = null;
            }    
            
            if( parent == null ) {
                mess = 'No Influence data available.';
                return;
            }
                
            try {
                myInf = [select id
                from Influence__c
                where user__c = :Userinfo.getuserid()
                and influence_parent__c = :parent.id
                order by ranking__c asc];
            } catch( Exception e ) {}
            
            // Log this viewing
            infTracker = new Influence_Tracker__c( influence_snapshot__c = parent.id, user__c = u.id );
            
            if( myInf == null || myInf.isEmpty() ) {
                mess += 'Couldn\'t find your Influence record in the system.<br/><br/>';
                infTracker.error__c = 'No Influence Record';
                
                try { 
                    if( parent.track_influence_reports__c )
                        insert infTracker;
                } catch( Exception e2 ) {}
                
                return;
            }
            
            infTracker.influence__c = myInf[0].id;
            
            // Send the email with our results
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            
            mail.setTargetObjectId( userinfo.getuserid() );
            mail.setWhatId( myInf[0].id );
            mail.setTemplateId( [select id from EmailTemplate where name ='Influence' limit 1].id ); 
            mail.setSenderDisplayName( 'Your Chatter Influence');
            mail.setBccSender(false); 
            mail.setUseSignature(false);
            mail.setSaveAsActivity(false);
        
            try {
                if( isTest ) throw new InfluenceException();
                
                Messaging.sendEmail( new Messaging.SingleEmailMessage[] { mail } );
                mess += '<strong>Success!</strong> Emailed your Influence score to '+ u.email +'.<br/><br/>';
            } catch( Exception e ) {
                ApexPages.addMessages(e);
                
                mess += '<strong>Failed</strong> to send your Influence email.<br/><br/>';
                
                infTracker.error__c = 'Failed Email';
                
                try { 
                    if( parent.track_influence_reports__c )
                        insert infTracker;
                } catch( Exception e2 ) {}
                
                return;
            }
            
            infTracker.success__c = true;
            infTracker.error__c = '';
            
            try {
                if( parent.track_influence_reports__c )
                    insert infTracker;
            } catch( Exception e ) {
                ApexPages.addMessages(e);
            }
    }
    
    // Get a listing of the historical snapshots eligible to view on the leaderboard
    public SelectOption[] getSnapshots() {
        SelectOption[] so = new SelectOption[] {};
        
        so.add( new SelectOption( '', '-- Select a Snapshot --' ) );
        
        for( Influence_Parent__c ip : [select id, start_time__c, end_time__c
            from Influence_Parent__c
            where active__c = true and leaderboard_status__c <> null and leaderboard_status__c <> 'No Leaderboard'
            and start_time__c <> null and end_time__c <> null
            order by end_time__c desc limit :( isTest ? 5 : 1000 )] )
            so.add( new SelectOption( ip.id, 'Snapshot: '+ ip.start_time__c.format('MMM dd yyyy h:mm') +' — '+ ip.end_time__c.format('MMM dd yyyy h:mm') ) );
        
        return so;
    }
    
    // Force a recalc of the departments when we choose a snapshot
    public void calcDepartments() {
        if( ipID != null && ipID != '' )
            ip = [select id, leaderboard_status__c 
                from Influence_Parent__c
                where id = :ipID];
            
        getDepartments();
        changeDept();
    }
    
    // Get a listing of the departments available to browse for this parent
    public SelectOption[] getDepartments() {
        SelectOption[] so = new SelectOption[] {};
        
        if( ipID == '' )
            so.add( new SelectOption( '', '-- Select a Snapshot to browse by Department --' ) );
        else {
            so.add( new SelectOption( '', 'Overall Leaderboard' ) );
        
            for( AggregateResult ar : [select user__r.department dept, count(id) from Influence__c
                where influence_parent__c = :ipID
                and user__r.department <> null
                group by user__r.department
                having count(id) > 0
                order by user__r.department asc] )
            so.add( new SelectOption( string.valueof( ar.get('dept') ), string.valueof( ar.get('dept') ) ) );
        }
        
        return so;
    }
    
    // Get a listing of influence records for a given department
    public void changeDept() {                     
        rankings = Database.query('select id, user__r.name, user__r.department, user__r.smallphotourl, chatterrank__c, ranking__c '+
            'from Influence__c '+
            'where influence_parent__c = :ipID '+
            'and user__c <> null '+
            ( dept == null || dept == '' ? '' : 'and user__r.department = :dept ' ) +
            'order by ranking__c asc limit '+ (isTest ? 5 : 1000) );
    }
    
    public static testmethod void runICTest() {
        influencecontroller ic = new influencecontroller();
        ic.isTest = true;
        ic.getSnapshots();
        ic.getDepartments();
        ic.calcDepartments();
        ic.changeDept();
        
        ic.sendInfluence();     
        
        // New Inf parent
        Influence_Parent__c ip = new Influence_Parent__c( active__c = true,  maximum_concurrent_batches__c = 5, track_influence_reports__c = true, start_time__c = datetime.now().addMonths(-12), end_time__c = datetime.now() );
        insert ip;
        
        ic = new influencecontroller();
        ic.ipID = ip.id;
        ic.calcDepartments();
        
        if( ic.getDepartments().size() > 1 ) {
            ic.dept = ic.getDepartments().get(1).getLabel();
            ic.changeDept();
        }
        
        system.assertNotEquals( '', ic.updated );
        
        ic.sendInfluence();
        
        Influence_Tracker__c it = [select id from Influence_Tracker__c where success__c = false and influence_snapshot__c = :ip.id and user__c = :userinfo.getuserid() ];
        
        system.assertNotEquals( null, it.id );
        
        // New inf
        Influence__c inf = new Influence__c( influence_parent__c = ip.id, user__c = userinfo.getuserid(), pc_rank__c = 1, cc_rank__c = 1,
            pr_rank__c = 1, cr_rank__c = 1, f_rank__c = 1, ranking__c = 1, aip_rank__c = 1, acd_rank__c = 1, likes_received_rank__c = 1 );
        insert inf;
        
        ic = new influencecontroller();
        
        ic.sendInfluence();
        
        it = [select id from Influence_Tracker__c where success__c = true and influence_snapshot__c = :ip.id and user__c = :userinfo.getuserid() ];
        
        system.assertNotEquals( null, it.id );
    }
}