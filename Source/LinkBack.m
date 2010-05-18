//
//  LinkBack.m
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

#import "LinkBack.h"
#import "LinkBackServer.h"

NSString* LinkBackPboardType = @"LinkBackData" ;

// LinkBack data keys.  These are used in a LinkBack object, which is currently a dictionary.  Do not depend on these values.  They are public for testing purposes only.
NSString* LinkBackServerNameKey = @"serverName" ;
NSString* LinkBackServerBundleIdentifierKey = @"bundleId" ;
NSString* LinkBackVersionKey = @"version" ;
NSString* LinkBackApplicationDataKey = @"appData" ;

// ...........................................................................
// Support Functions
//

id MakeLinkBackData(NSString* serverName, id appData) 
{
    NSMutableDictionary* ret = [[NSMutableDictionary alloc] init] ;
    NSString* bundleId = [[NSBundle mainBundle] bundleIdentifier] ;
    id version = @"A" ;
    
    [ret setObject: bundleId forKey: LinkBackServerBundleIdentifierKey]; 
    [ret setObject: serverName forKey: LinkBackServerNameKey] ;
    [ret setObject: version forKey: LinkBackVersionKey] ;
    [ret setObject: appData forKey: LinkBackApplicationDataKey] ;
    return [ret autorelease] ;
}

id LinkBackGetAppData(id LinkBackData) 
{
    return [LinkBackData objectForKey: LinkBackApplicationDataKey] ;
}

NSString* LinkBackUniqueItemKey() 
{
    static int counter = 0 ;
    
    NSString* base = [[NSBundle mainBundle] bundleIdentifier] ;
    unsigned long time = [NSDate timeIntervalSinceReferenceDate] ;
    return [NSString stringWithFormat: @"%@%.8x.%.4x",base,time,counter++] ;
}

BOOL LinkBackDataBelongsToActiveApplication(id data) 
{
    NSString* bundleId = [[NSBundle mainBundle] bundleIdentifier] ;
    NSString* dataId = ([data isKindOfClass: [NSDictionary class]]) ? [data objectForKey: LinkBackServerBundleIdentifierKey] : nil ;
    return (dataId && [dataId isEqualToString: bundleId]) ;
}

// ...........................................................................
// LinkBackServer 
//
// one of these exists for each registered server name.  This is the receiver of server requests.

// ...........................................................................
// LinkBack Class
//

NSMutableDictionary* keyedLinkBacks = nil ;

@implementation LinkBack

+ (void)initialize
{
    static BOOL inited = NO ;
    if (inited) return ;
    inited=YES; [super initialize] ;
    keyedLinkBacks = [[NSMutableDictionary alloc] init] ;
}

+ (LinkBack*)activeLinkBackForItemKey:(id)aKey 
{
    return [keyedLinkBacks objectForKey: aKey] ;
}

- (id)initServerWithClient: (LinkBack*)aLinkBack delegate: (id<LinkBackServerDelegate>)aDel 
{
    if (self = [super init]) {
        peer = [aLinkBack retain] ;
        sourceName = [[peer sourceName] copy] ;
        key = [[peer itemKey] copy] ;
        isServer = YES ;
        delegate = aDel ;
        [keyedLinkBacks setObject: self forKey: key] ;
    }
    
    return self ;
}

- (id)initClientWithSourceName:(NSString*)aName delegate:(id<LinkBackClientDelegate>)aDel itemKey:(NSString*)aKey ;
{
    if (self = [super init]) {
        isServer = NO ;
        delegate = aDel ;
        sourceName = [aName copy] ;
        pboard = [[NSPasteboard pasteboardWithUniqueName] retain] ;
        key = [aKey copy] ;
    }
    
    return self ;
}

- (void)dealloc
{
    [repobj release] ;
    [sourceName release] ;
    
    if (peer) [self closeLink] ;
    [peer release] ;
    
    if (!isServer) [pboard releaseGlobally] ; // client owns the pboard.
    [pboard release] ;
    
    [super dealloc] ;
}

// ...........................................................................
// General Use methods

- (NSPasteboard*)pasteboard 
{
    return pboard ;
}

- (id)representedObject 
{
    return repobj ;
}

- (void)setRepresentedObject:(id)obj 
{
    [obj retain] ;
    [repobj release] ;
    repobj = obj ;
}

- (NSString*)sourceName
{
    return sourceName ;
}

- (NSString*)itemKey
{
    return key ;
}

// this method is called to initial a link closure from this side.
- (void)closeLink 
{
    // inform peer of closure
    if (peer) {
        [peer remoteCloseLink] ; 
        [peer release] ;
        peer = nil ;
        [self release] ;
        [keyedLinkBacks removeObjectForKey: [self itemKey]]; 
    }
}

// this method is called whenever the link is about to be or has been closed by the other side.
- (void)remoteCloseLink 
{
    if (peer) {
        [peer release] ;
        peer = nil ;
        [self release] ;
        [keyedLinkBacks removeObjectForKey: [self itemKey]]; 
    }

    if (delegate) [delegate linkBackDidClose: self] ;
}

// ...........................................................................
// Server-side methods
//
+ (BOOL)publishServerWithName:(NSString*)name delegate:(id<LinkBackServerDelegate>)del 
{
    return [LinkBackServer publishServerWithName: name delegate: del] ;
}

+ (void)retractServerWithName:(NSString*)name 
{
    LinkBackServer* server = [LinkBackServer LinkBackServerWithName: name] ;
    if (server) [server retract] ;
}

- (void)sendEdit 
{
    if (!peer) [NSException raise: NSGenericException format: @"tried to request edit from a live link not connect to a server."] ;
    [peer refreshEditWithPasteboardName: [pboard name]] ;
}

// FROM CLIENT LinkBack
- (void)requestEditWithPasteboardName:(bycopy NSString*)pboardName
{
    // get the new pasteboard, if needed
    if ((!pboard) || ![pboardName isEqualToString: [pboard name]]) pboard = [[NSPasteboard pasteboardWithName: pboardName] retain] ;

    // pass onto delegate
	[delegate performSelectorOnMainThread: @selector(linkBackClientDidRequestEdit:) withObject: self waitUntilDone: NO] ;
}

// ...........................................................................
// Client-Side Methods
//
+ (LinkBack*)editLinkBackData:(id)data sourceName:(NSString*)aName delegate:(id<LinkBackClientDelegate>)del itemKey:(NSString*)aKey
{
    // if an active live link already exists, use that.  Otherwise, create a new one.
    LinkBack* ret = [keyedLinkBacks objectForKey: aKey] ;
    
    if(nil==ret) {
        BOOL ok ;
        NSString* serverName ;
        NSString* serverId ;
        
        // collect server contact information from data.
        ok = [data isKindOfClass: [NSDictionary class]] ;
        if (ok) {
            serverName = [data objectForKey: LinkBackServerNameKey] ;
            serverId = [data objectForKey: LinkBackServerBundleIdentifierKey];
        }
        
        if (!ok || !serverName || !serverId) [NSException raise: NSInvalidArgumentException format: @"LinkBackData is not of the correct format: %@", data] ;
        
        // create the live link object and try to connect to the server.
        ret = [[LinkBack alloc] initClientWithSourceName: aName delegate: del itemKey: aKey] ;
        
        if (![ret connectToServerWithName: serverName inApplication: serverId]) {
            [ret release] ;
            ret = nil ;
        }
    }
    
    // now with a live link in hand, request an edit
    if (ret) {
        // if connected to server, publish data and inform server.
        NSPasteboard* my_pboard = [ret pasteboard] ;
        [my_pboard declareTypes: [NSArray arrayWithObject: LinkBackPboardType] owner: ret] ;
        [my_pboard setPropertyList: data forType: LinkBackPboardType] ;
        
        [ret requestEdit] ;
        
    // if connection to server failed, return nil.
    } else {
        [ret release] ;
        ret = nil ;
    }
    
    return ret ;
}

- (BOOL)connectToServerWithName:(NSString*)aName inApplication:(NSString*)bundleIdentifier 
{
    // get the LinkBackServer.
    LinkBackServer* server = [LinkBackServer LinkBackServerWithName: aName inApplication: bundleIdentifier launchIfNeeded: YES] ;
    if (!server) return NO ; // failed to get server
    
    peer = [[server initiateLinkBackFromClient: self] retain] ;
    if (!peer) return NO ; // failed to initiate session
    
    // if we connected, then add to the list of active keys
    [keyedLinkBacks setObject: self forKey: [self itemKey]] ;
    
    return YES ;
}

- (void)requestEdit 
{
    if (!peer) [NSException raise: NSGenericException format: @"tried to request edit from a live link not connect to a server."] ;
    [peer requestEditWithPasteboardName: [pboard name]] ;
}

// RECEIVED FROM SERVER
- (void)refreshEditWithPasteboardName:(bycopy NSString*)pboardName
{
    // if pboard has changes, change to new pboard.
    if (![pboardName isEqualToString: [pboard name]]) {
        [pboard release] ;
        pboard = [[NSPasteboard pasteboardWithName: pboardName] retain] ;
    } 
    
    // inform delegate
	[delegate performSelectorOnMainThread: @selector(linkBackServerDidSendEdit:) withObject: self waitUntilDone: NO] ;
}

@end
