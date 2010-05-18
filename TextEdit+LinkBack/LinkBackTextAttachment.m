//
//  LinkBackTextAttachment.m
//  TextEdit
//
//  Created by Charles Jolley on Tue Jun 15 2004.
//  Copyright (c) 2004 __MyCompanyName__. All rights reserved.
//

#import "LinkBackTextAttachment.h"
#import <LinkBack/LinkBack.h> 

@implementation LinkBackTextAttachment

- (void)dealloc
{
    if (_linkBackData) [_linkBackData release]; 
    if (_linkBackItemKey) [_linkBackItemKey release] ;
    [super dealloc] ;
}

- (id)linkBackData 
{
    return _linkBackData ;
}

- (void)setLinkBackData:(id)dta 
{
    _linkBackData = [dta copy] ;
}

- (id)linkBackItemKey 
{
    if (!_linkBackItemKey) [self setLinkBackItemKey: LinkBackUniqueItemKey()] ;
    return _linkBackItemKey ;
}

- (void)setLinkBackItemKey:(id)key 
{
    key = [key copy] ;
    [_linkBackItemKey release] ;
    _linkBackItemKey = key;
}

@end
