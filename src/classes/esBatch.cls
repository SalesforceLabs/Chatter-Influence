// Jonathan Hersh - jhersh@salesforce.com - 12/2010
// Follower batch calculator

global class esBatch implements Database.Batchable<sObject>, Database.Stateful {

    global String ipID;
    global Influence_Parent__c ip	{ get; set; }
    global Set<ID> exclude			{ get; set; }
    global static string userPrefix = Schema.Sobjecttype.User.getKeyPrefix();
    global boolean isTest			{ get; set; }
    
    global esBatch() { 
    	isTest = false;
    }

    global Database.QueryLocator start(Database.BatchableContext BC){        
    	try {
    		ip = [select id, start_time__c, end_time__c from Influence_Parent__c where id = :ipID];
    	} catch( Exception e ) {
    		return null;
    	}
    	
    	string eList = '';
    	
    	if( exclude == null )
    		exclude = new Set<ID> ();
    		
    	ID[] excludeIDs = new ID[] {};
    	excludeIDs.addAll( exclude );	
    		
    	for( integer x = 0; x < excludeIDs.size(); x++ )
    		eList += '\''+ excludeIDs.get(x) + '\'' + ( x < excludeIDs.size() - 1 ? ',' : '' );
    		
    	eList = '(' + eList + ')';
    		    	    
        string q = 'select parentid from EntitySubscription '+
        	'where createddate >= '+ influenceBatcher.soqlDate( ip.start_time__c ) +' and createddate <= '+ influenceBatcher.soqlDate( ip.end_time__c ) +' '+
        	( !excludeIDs.isEmpty() ? ' and parentid NOT IN '+ eList +' and subscriberid NOT IN '+ eList : '' ) +' '+
        	' order by createddate desc, id desc '+ ( isTest ? 'limit 200' : '' );
        
        return Database.getQueryLocator(q);
    }

    global void execute(Database.BatchableContext BC, List<sObject> scope){
        string[] userIDs = new string[] {};
        
        // Try to recover if something really wrong happens
        try {
    		ip = [select id, start_time__c, end_time__c from Influence_Parent__c where id = :ipID];
    	} catch( Exception e ) {
    		return;
    	}
        
        for( sObject s : scope )
        	if( string.valueof( s.get('parentid') ).substring(0,3)  == userPrefix )
            	userIDs.add( string.valueof( s.get('parentid') ) );
            	
        // All non-users?
        if( userIDs.isEmpty() )
        	return;
            
        Map<ID,User> us = new Map<ID,User> ([select id from User where id IN :userIDs and isactive=true and 
        	( usertype='Standard' or usertype='CSNOnly' )]);
            
        // Get the influence records for these users
        Influence__c[] infs = [select id, user__c, influence_parent__c, followers__c
            from Influence__c
            where user__c IN :us.keySet()
            and influence_parent__c = :ipID];
            
        Map<ID, Influence__c> infMap = new Map<ID, Influence__c> ();
        
        for( Influence__c inf : infs )
            infMap.put( inf.user__c, inf );
            
        for( sObject s : scope ) {
            string key = string.valueof( s.get('parentid') );
            
            if( key.substring( 0, 3 ) != userPrefix || !us.containsKey( key ) )
            	continue;
            
            if( !infMap.containsKey( key ) )
                infMap.put( key, new Influence__c( influence_parent__c = ipID, 
                    user__c = key ) );
            
            Influence__c inf = infMap.get( key );
            
            inf.followers__c = ( inf.followers__c == null || inf.followers__c == 0 ? 1 : inf.followers__c + 1 );
                
            infMap.put( key, inf );
        }
        
        try {
        	upsert infMap.values();
        } catch( Exception e ) {}
    }

    global void finish(Database.BatchableContext BC) { 
        try {
        	Influence_Parent__c ip = [select id, jobs_executed__c, status__c from Influence_Parent__c where id = :ipID];	
       	
       		ip.status__c = 'Sorting Data';
       		
       		update ip;  
        } catch( Exception e ) {}
    }
    
   global static testmethod void runESTest() {
    	// New Inf parent
    	Influence_Parent__c ip = new Influence_Parent__c( active__c = true,  maximum_concurrent_batches__c = 5, start_time__c = datetime.now().addMonths(-6), end_time__c = datetime.now() );
    	insert ip;
    	
    	// New user for us to follow
    	Profile p = [select id from Profile where usertype='Standard' limit 1];
    	User u = new User(alias = 'standt', email='standarduser@kwutang.demo', 
                        emailencodingkey='UTF-8', lastname='Testing1', firstname='Testing', languagelocalekey='en_US', 
                        localesidkey='en_US', profileid = p.Id, 
                        timezonesidkey='America/Los_Angeles', username='standarduser@kwutang.demo');        
        
        try {
        	insert u;
        	insert new EntitySubscription( parentid = userinfo.getuserid(), subscriberid = u.id );
        } catch( Exception e ) {
        	return;
        }
	    
	    esBatch eb = new esBatch();
	    eb.isTest = true;
	    eb.ipID = ip.id;
	    eb.exclude = new Set<ID> { userinfo.getuserid() };

		Test.StartTest();
	    ID batchprocessid = Database.executeBatch(eb);
	    Test.StopTest();
    }
}