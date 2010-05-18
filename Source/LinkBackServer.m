//
//  LinkBackServer.m
//  LinkBack
//
//  Created by Charles Jolley on Tue Jun 15 2004.
//  Copyright (c) 2004, Nisus Software, Inc.
//  All rights reserved.

//  Redistribution and use in source and binary forms, with or without 
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, 
//  this list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright notice, 
//  this list of conditions and the following disclaimer in the documentation 
//  and/or other materials provided with the distribution.
//
//  Neither the name of the Nisus Software, Inc. nor the names of its 
//  contributors may be used to endorse or promote products derived from this 
//  software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS 
//  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, 
//  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR 
//  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
//  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
//  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
//  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING 
//  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "LinkBackServer.h"
#import "LinkBack.h"

NSString* MakeLinkBackServerName(NSString* bundleIdentifier, NSString* name)
{
    return [bundleIdentifier stringByAppendingFormat: @":%@",name] ;
}

NSMutableDictionary* LinkBackServers = nil ;

@implementation LinkBackServer

+ (void)initialize
{
    static BOOL inited = NO ;
    if (inited) return ;

    [super initialize] ; 
    inited = YES ;
    
    if (!LinkBackServers) LinkBackServers = [[NSMutableDictionary alloc] init];
}

+ (LinkBackServer*)LinkBackServerWithName:(NSString*)aName  
{
    return [LinkBackServers objectForKey: aName] ;
}

+ (BOOL)publishServerWithName:(NSString*)aName delegate:(id<LinkBackServerDelegate>)del 
{
    LinkBackServer* serv = [[LinkBackServer alloc] initWithName: aName delegate: del] ;
    BOOL ret = [serv publish] ; // retains if successful
    [serv release] ;
    return ret ;
}

+ (LinkBackServer*)LinkBackServerWithName:(NSString*)aName inApplication:(NSString*)bundleIdentifier launchIfNeeded:(BOOL)flag 
{
	NSString* serverName = MakeLinkBackServerName(bundleIdentifier, aName) ;
    id ret = nil ;
	NSTimeInterval tryMark ;
	
	// Let see if its already running
	BOOL appLaunched = FALSE;
    NSArray *appsArray = [[NSWorkspace sharedWorkspace] launchedApplications];
	NSEnumerator *appsArrayEnumerator = [appsArray objectEnumerator];
	NSDictionary *appDict;
	NSString *appBundleIdentifier;
	while (appDict = [appsArrayEnumerator nextObject]) 
	{
		appBundleIdentifier = [appDict objectForKey:@"NSApplicationBundleIdentifier"];
		if((appBundleIdentifier) && ([appBundleIdentifier isEqualToString:bundleIdentifier]))
			appLaunched = TRUE;
	}	
	
    // if flag, and not launched try to launch.
	if((!appLaunched) && (flag))
		[[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier: bundleIdentifier options: (NSWorkspaceLaunchWithoutAddingToRecents | NSWorkspaceLaunchWithoutActivation) additionalEventParamDescriptor: nil launchIdentifier: nil] ;
    
    // now, try to connect.  retry connection for a while if we did not succeed at first.  This gives the app time to launch.
	tryMark = [NSDate timeIntervalSinceReferenceDate] ;
	do {
		ret = [NSConnection rootProxyForConnectionWithRegisteredName: serverName host: nil] ;
	} while ((!ret) && (([NSDate timeIntervalSinceReferenceDate]-tryMark)<10)) ;

    [ret setProtocolForProxy: @protocol(LinkBackServer)] ;
    
    return ret ;
}

- (id)initWithName:(NSString*)aName delegate:(id<LinkBackServerDelegate>)aDel
{
    if (self = [super init]) {
        name = [aName copy] ;
        delegate = aDel ;
        listener = nil ;
    }
    
    return self ;
}

- (void)dealloc
{
    if (listener) [self retract] ;
    [name release] ;
    [super dealloc] ;
}

- (BOOL)publish
{
    NSString* serverName = MakeLinkBackServerName([[NSBundle mainBundle] bundleIdentifier], name) ;
    BOOL ret = YES ;
    
    // create listener and connect
    NSPort* port = [NSPort port] ;
    listener = [NSConnection connectionWithReceivePort: port sendPort:port] ;
    [listener setRootObject: self] ;
    ret = [listener registerName: serverName] ;
    
    // if successful, retain connection and add self to list of servers.
    if (ret) {
        [listener retain] ;
        [LinkBackServers setObject: self forKey: name] ;
    } else listener = nil ; // listener will dealloc on its own. 
    
    return ret ;
}

- (void)retract 
{
    if (listener) {
        [listener invalidate] ;
        [listener release] ;
        listener = nil ;
    }
    
    [LinkBackServers removeObjectForKey: name] ;
}

- (LinkBack*)initiateLinkBackFromClient:(LinkBack*)clientLinkBack 
{
    LinkBack* ret = [[LinkBack alloc] initServerWithClient: clientLinkBack delegate: delegate] ;
    
    // NOTE: we do not release because LinkBack will release itself when it the link closes. (caj)
    
    return ret ; 
}

@end
