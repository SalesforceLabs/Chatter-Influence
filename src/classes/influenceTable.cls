// Jonathan Hersh - jhersh@salesforce.com - Dec '10

public with sharing class influenceTable {
    public ID userID         { get; set; }
    public ID ipID              { get; set; }
    public influence_parent__c ip    { get; set; }
    public User u            { get; set; }
    public integer deptRank     { get; set; }
    public integer deptSize     { get; set; }
    public integer globalSize   { get; set; }
    
    public influenceTable() {}
    
    public infLine[] getMetrics() {
        infLine[] infs = new infLine[] {};
        
        try {
            u = [select id, name, email, department, firstname
            from User
            where id = :userID];
        } catch( Exception e ) {
            return null;
        }
        
        try {
            ip = [select id, total_records__c, posts_created_sum__c,
            median_posts_created__c, posts_received_sum__c, median_posts_received__c,
            comments_created_sum__c, median_comments_created__c, comments_received_sum__c,
            median_comments_received__c, median_day_comments__c,
            avg_day_comments_sum__c, influence_sum__c,
            median_influence__c, followers_sum__c, median_followers__c, median_likes_received__c,
            likes_received_sum__c, avg_interactions_post__c, median_interactions_post__c
            from Influence_Parent__c
            where id = :ipID];
        } catch( Exception e ) {
            return null;
        }
            
        Influence__c myInf;
        
        try {
            myInf = [select id, pc_rank__c, pr_rank__c, cc_rank__c, cr_rank__c,
            acd_rank__c, influence_formula__c, 
            comments_per_day__c, posts_created__c, posts_received__c, comments_created__c,
            comments_received__c, followers__c, days_with_comments__c, influence_parent__c,
            ranking__c, f_rank__c, likes_received__c, likes_received_rank__c, avg_interactions_post__c,
            aip_rank__c, chatterrank__c
            from Influence__c
            where influence_parent__c = :ip.id
            and user__c = :u.id
            order by ranking__c asc limit 1];
        } catch( Exception e ) {
            return null;
        }
        
        // Get the influence scores for everyone else in our department
        Influence__c[] deptInfs = [select id, pc_rank__c, pr_rank__c, cc_rank__c, cr_rank__c,
            acd_rank__c, influence_formula__c, 
            comments_per_day__c, posts_created__c, posts_received__c, comments_created__c,
            comments_received__c, followers__c, days_with_comments__c, ranking__c, f_rank__c,
            likes_received__c, likes_received_rank__c, avg_interactions_post__c, aip_rank__c,
            chatterrank__c
            from Influence__c
            where influence_parent__c = :ip.id
            and user__r.department = :u.department
            and user__r.isactive = true
            and user__r.usertype = 'Standard'
            order by ranking__c asc limit 950];
            
        Double[] scores;
        Integer counter;
        
        // First, rank against our dept's PC score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.pc_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.pc_rank__c )
                break;
        }
        
        infLine il = new infLine();
        il.metric = 'Posts Created<sup>1</sup>';
        il.avgNum = ip.posts_created_sum__c / ip.total_records__c;
        il.medNum = ip.median_posts_created__c;
        il.myVal = myInf.posts_created__c;
        il.myRank = myInf.pc_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = true;
        
        infs.add( il ); 
        
        // PR score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.pr_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.pr_rank__c )
                break;
        }
        
        il = new infLine();
        il.metric = 'Posts Received<sup>2</sup>';
        il.avgNum = ip.posts_received_sum__c / ip.total_records__c;
        il.medNum = ip.median_posts_received__c;
        il.myVal = myInf.posts_received__c;
        il.myRank = myInf.pr_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = true;
        
        infs.add( il );      
        
        // CC score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.cc_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.cc_rank__c )
                break;
        }
        
        il = new infLine();
        il.metric = 'Comments Created';
        il.avgNum = ip.comments_created_sum__c / ip.total_records__c;
        il.medNum = ip.median_comments_created__c;
        il.myVal = myInf.comments_created__c;
        il.myRank = myInf.cc_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = true;
        
        infs.add( il );     
        
        // CR score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.cr_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.cr_rank__c )
                break;
        }
        
        il = new infLine();
        il.metric = 'Comments Received<sup>3</sup>';
        il.avgNum = ip.comments_received_sum__c / ip.total_records__c;
        il.medNum = ip.median_comments_received__c;
        il.myVal = myInf.comments_received__c;
        il.myRank = myInf.cr_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = true;
        
        infs.add( il ); 
        
        // Likes Received score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.likes_received_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.likes_received_rank__c )
                break;
        }
        
        il = new infLine();
        il.metric = 'Likes Received';
        il.avgNum = ip.likes_received_sum__c / ip.total_records__c;
        il.medNum = ip.median_likes_received__c;
        il.myVal = myInf.likes_received__c;
        il.myRank = myInf.likes_received_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = true;
        
        infs.add( il ); 
        
        // F score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.f_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.f_rank__c )
                break;
        }
        
        il = new infLine();
        il.metric = 'New Followers';
        il.avgNum = ip.followers_sum__c / ip.total_records__c;
        il.medNum = ip.median_followers__c;
        il.myVal = myInf.followers__c;
        il.myRank = myInf.f_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = true;
        
        infs.add( il );  
        
        // AIP score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.aip_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.aip_rank__c )
                break;
        }
        
        il = new infLine();
        il.metric = 'Avg. Interactions Received/Post';
        il.avgNum = ip.avg_interactions_post__c;
        il.medNum = ip.median_interactions_post__c;
        il.myVal = myInf.avg_interactions_post__c;
        il.myRank = myInf.aip_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = false;
        
        infs.add( il );  
        
        // ACD score
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.acd_rank__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.acd_rank__c )
                break;
        }
        
        il = new infLine();
        il.metric = 'Avg. Interactions Received/Day<sup>4</sup>';
        il.avgNum = ip.avg_day_comments_sum__c / ip.total_records__c;
        il.medNum = ip.median_day_comments__c;
        il.myVal = myInf.comments_per_day__c;
        il.myRank = myInf.acd_rank__c.intvalue();
        il.deptRank = counter;
        il.isInteger = false;
        
        infs.add( il ); 
        
        // ChatterRank
        scores = new Double[] {};
        counter = 0;
        
        for( Influence__c inf : deptInfs )
            scores.add( inf.ranking__c );
            
        scores.sort();
            
        for( Double i : scores ) {
            counter++;
            if( i == myInf.ranking__c )
                break;
        }
        
        il = new infLine();
        il.metric = '<strong>ChatterRank</strong><sup>5</sup>';
        il.avgNum = null; //ip.influence_sum__c / ip.total_records__c;
        il.medNum = null; // ip.median_influence__c;
        il.myVal = myInf.chatterrank__c;
        il.myRank = myInf.ranking__c.intvalue();
        il.deptRank = counter;
        il.isInteger = true;
        
        infs.add( il ); 
        
        deptRank = counter;
        deptSize = deptInfs.size();
        globalSize = ip.total_records__c.intvalue();
            
        return infs;
    }   

    public class infLine {
        public string metric    { get; set; }
        public double avgNum    { get; set; }
        public double medNum    { get; set; }
        public double myVal     { get; set; }
        public integer myRank   { get; set; }
        public integer deptRank { get; set; }
        public boolean isInteger  { get; set; }
    }
    
    public static testmethod void runTest() {
        // New Inf parent
        Influence_Parent__c ip = new Influence_Parent__c( active__c = true, start_time__c = datetime.now().addMonths(-12), end_time__c = datetime.now() );
        insert ip;
        
        // New inf
        Influence__c inf = new Influence__c( influence_parent__c = ip.id, user__c = userinfo.getuserid(), pc_rank__c = 1, cc_rank__c = 1,
            pr_rank__c = 1, cr_rank__c = 1, f_rank__c = 1, ranking__c = 1, aip_rank__c = 1, acd_rank__c = 1, likes_received_rank__c = 1 );
        insert inf;
        
        influenceTable it = new influenceTable();
        it.userid = userinfo.getuserid();
        it.ipID = ip.id;
        
        infLine[] infs = new infLine[] {};
        
        infs = it.getMetrics();
        
        system.assertEquals( 9, infs.size() );
    }
}