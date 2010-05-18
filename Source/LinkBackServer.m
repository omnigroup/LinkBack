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

BOOL LinkBackServerIsSupported(NSString* name, id supportedServers)
{
	BOOL ret = NO ;
	int idx ;
	NSString* curServer = supportedServers ;
	
	// NOTE: supportedServers may be nil, an NSArray, or NSString.
	if (supportedServers) {
		if ([supportedServers isKindOfClass: [NSArray class]]) {
			idx = [supportedServers count] ;
			while((NO==ret) && (--idx >= 0)) {
				curServer = [supportedServers objectAtIndex: idx] ;
				ret = [curServer isEqualToString: name] ;
			}
		} else ret = [curServer isEqualToString: name] ; 
	}
	
	return ret ;
}

NSString* FindLinkBackServer(NSString* bundleIdentifier, NSString* serverName, NSString* dir, int level)
{
	NSString* ret = nil ;

	NSFileManager* fm = [NSFileManager defaultManager] ;
	NSArray* contents = [fm directoryContentsAtPath: dir] ;
	int idx ;

	NSLog(@"searching for %@ in folder: %@", serverName, dir) ;
	
	// working info
	NSString* cpath ;
	NSBundle* cbundle ;
	NSString* cbundleIdentifier ;
	id supportedServers ;

	// resolve any symlinks, expand tildes.
	dir = [dir stringByStandardizingPath] ;
	
	// find all .app bundles in the directory and test them.
	idx = (contents) ? [contents count] : 0 ;
	while((nil==ret) && (--idx >= 0)) {
		cpath = [contents objectAtIndex: idx] ;
		
		if ([[cpath pathExtension] isEqualToString: @"app"]) {
			cpath = [dir stringByAppendingPathComponent: cpath] ;
			cbundle = [NSBundle bundleWithPath: cpath] ;
			cbundleIdentifier = [cbundle bundleIdentifier] ;
			
			if ([cbundleIdentifier isEqualToString: bundleIdentifier]) {
				supportedServers = [[cbundle infoDictionary] objectForKey: @"LinkBackServer"] ;
				ret= (LinkBackServerIsSupported(serverName, supportedServers)) ? cpath : nil ;
			}
		}
	}
	
	// if the app was not found, descend into non-app dirs.  only descend 4 levels to avoid taking forever.
	if ((nil==ret) && (level<4)) {
		idx = (contents) ? [contents count] : 0 ;
		while((nil==ret) && (--idx >= 0)) {
			BOOL isdir ;
			
			cpath = [contents objectAtIndex: idx] ;
			[fm fileExistsAtPath: cpath isDirectory: &isdir] ;
			if (isdir && (![[cpath pathExtension] isEqualToString: @"app"])) {
				cpath = [dir stringByAppendingPathComponent: cpath] ;
				ret = FindLinkBackServer(bundleIdentifier, serverName, cpath, level+1) ;
			}
		}
	}
	
	return ret ;
}

void LinkBackRunAppNotFoundPanel(NSString* appName, NSURL* url)
{
	int result ;
	
	// strings for panel
	NSBundle* b = [NSBundle bundleForClass: [LinkBack class]] ;
	NSString* title ;
	NSString* msg ;
	NSString* ok ;
	NSString* urlstr ;
	
	title = NSLocalizedStringFromTableInBundle(@"_AppNotFoundTitle", @"Localized", b, @"app not found title") ;
	ok = NSLocalizedStringFromTableInBundle(@"_OK", @"Localized", b, @"ok") ;

	msg = (url) ? NSLocalizedStringFromTableInBundle(@"_AppNotFoundMessageWithURL", @"Localized", b, @"app not found msg") : NSLocalizedStringFromTableInBundle(@"_AppNotFoundMessageNoURL", @"Localized", b, @"app not found msg") ;
	
	urlstr = (url) ? NSLocalizedStringFromTableInBundle(@"_GetApplication", @"Localized", b, @"Get application") : nil ;

	title = [NSString stringWithFormat: title, appName] ;
	
	result = NSRunCriticalAlertPanel(title, msg, ok, urlstr, nil) ;
	if (NSAlertAlternateReturn == result) {
		[[NSWorkspace sharedWorkspace] openURL: url] ;
	}
}

+ (LinkBackServer*)LinkBackServerWithName:(NSString*)aName inApplication:(NSString*)bundleIdentifier launchIfNeeded:(BOOL)flag fallbackURL:(NSURL*)url appName:(NSString*)appName ;
{
	BOOL connect = YES ;
	NSString* serverName = MakeLinkBackServerName(bundleIdentifier, aName) ;
    id ret = nil ;
	NSTimeInterval tryMark ;
	
	// Try to connect
	ret = [NSConnection rootProxyForConnectionWithRegisteredName: serverName host: nil] ;
	
    // if launchIfNeeded, and the connection was not available, try to launch.
	if((!ret) && (flag)) {
		NSString* appPath ;
		id linkBackServers ;
		
		// first, try to find the app with the bundle identifier
		appPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: bundleIdentifier] ;
		linkBackServers = [[[NSBundle bundleWithPath: appPath] infoDictionary] objectForKey: @"LinkBackServer"] ; 
		appPath = (LinkBackServerIsSupported(aName, linkBackServers)) ? appPath : nil ;
		
		// if the found app is not supported, we will need to search for the app ourselves.
		if (nil==appPath) appPath = FindLinkBackServer(bundleIdentifier, aName, @"/Applications",0);
		
		if (nil==appPath) appPath = FindLinkBackServer(bundleIdentifier, aName, @"~/Applications",0);
		
		if (nil==appPath) appPath = FindLinkBackServer(bundleIdentifier, aName, @"/Network/Applications",0);
		
		// if app path has been found, launch the app.
		if (appPath) {
			[[NSWorkspace sharedWorkspace] launchApplication: appName] ;
		} else {
			LinkBackRunAppNotFoundPanel(appName, url) ;
			connect = NO ;
		}
	}
    
    // if needed, try to connect.  
	// retry connection for a while if we did not succeed at first.  This gives the app time to launch.
	if (connect && (nil==ret)) {
		tryMark = [NSDate timeIntervalSinceReferenceDate] ;
		do {
			ret = [NSConnection rootProxyForConnectionWithRegisteredName: serverName host: nil] ;
		} while ((!ret) && (([NSDate timeIntervalSinceReferenceDate]-tryMark)<10)) ;
		
	}

	// setup protocol and return
    if (ret) [ret setProtocolForProxy: @protocol(LinkBackServer)] ;
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
