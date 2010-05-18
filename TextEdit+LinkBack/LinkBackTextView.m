//
//  LinkBackTextView.m
//  TextEdit
//
//  Created by Charles Jolley on Tue Jun 15 2004.
//  Copyright (c) 2004 __MyCompanyName__. All rights reserved.
//

#import "LinkBackTextView.h"
#import <LinkBack/LinkBack.h>
#import "LinkBackTextAttachment.h"

@implementation LinkBackTextView

- (BOOL)readSelectionFromPasteboard:(NSPasteboard*)pboard
{
    // trap pasteboards with LinkBack data and PDF/TIFF data.
    BOOL hasPDF = NO;
    BOOL hasTIFF = NO;
    BOOL hasLinkBack = NO;
    NSEnumerator* e  = [[pboard types] objectEnumerator] ;
    id type ;
    while(type = [e nextObject]) {
        if ([type isEqual: NSTIFFPboardType]) hasTIFF = YES ;
        if ([type isEqual: NSPDFPboardType]) hasPDF = YES ;
//        if ([type isEqual: LinkBackPboardType]) hasLinkBack = YES ;
        hasLinkBack = YES ;
    }
    
    if (hasLinkBack && (hasPDF || hasTIFF)) {
        
        // construct a file wrapper with the graphic from the pasteboard.
        NSString* fileName = [NSString stringWithFormat: @"_%.8x.%@", [pboard changeCount], ((hasPDF) ? @"pdf" : @"tiff")];
        NSData* dta = [pboard dataForType: (hasPDF) ? NSPDFPboardType : NSTIFFPboardType] ;
        NSFileWrapper* fw = [[NSFileWrapper alloc] initRegularFileWithContents: dta] ;
        [fw setPreferredFilename: fileName] ;
        
        // construct the cell to display the attachment
        NSImage* img = [[NSImage alloc] initWithData: dta] ; 
        NSTextAttachmentCell* cell = [[NSTextAttachmentCell alloc] initImageCell: img] ;

        // construct a text attachment
        LinkBackTextAttachment* ta = [[LinkBackTextAttachment alloc] initWithFileWrapper: fw] ;
        [cell setAttachment: ta] ;
        [ta setAttachmentCell: cell] ;
        
        id linkBackData = [pboard propertyListForType: LinkBackPboardType] ;
        [ta setLinkBackData: linkBackData] ;
        
        // generate attributed string
        NSAttributedString* as = [NSAttributedString attributedStringWithAttachment: ta] ;
        NSRange srange = [self selectedRange] ;
        [[self textStorage] replaceCharactersInRange: srange withAttributedString: as] ;
        
        // clean up
        [ta release] ;
        [cell release] ;
        [img release] ;
        [fw release] ;
        
        return YES ;
    } else return [super readSelectionFromPasteboard: pboard] ;
    
}

@end
