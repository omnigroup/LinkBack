/*
        Controller.m
        Copyright (c) 1995-2003 by Apple Computer, Inc., all rights reserved.
        Author: Ali Ozer

	TextEdit milestones:
	Initially created 1/28/95
	Multiple page support 2/16/95
	Preferences panel 10/24/95
	HTML 7/3/97
	Exported services 8/1/97
	Java version created 8/11/97
	Undo 9/17/97
	Scripting 6/18/98
        Aquafication 11/1/99
        Encoding customization 5/20/02
 
	TODO: Use URLs, switch to NSDocument

        Central controller object for TextEdit.
*/
/*
 IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc. ("Apple") in
 consideration of your agreement to the following terms, and your use, installation, 
 modification or redistribution of this Apple software constitutes acceptance of these 
 terms.  If you do not agree with these terms, please do not use, install, modify or 
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and subject to these 
 terms, Apple grants you a personal, non-exclusive license, under Apple's copyrights in 
 this original Apple software (the "Apple Software"), to use, reproduce, modify and 
 redistribute the Apple Software, with or without modifications, in source and/or binary 
 forms; provided that if you redistribute the Apple Software in its entirety and without 
 modifications, you must retain this notice and the following text and disclaimers in all 
 such redistributions of the Apple Software.  Neither the name, trademarks, service marks 
 or logos of Apple Computer, Inc. may be used to endorse or promote products derived from 
 the Apple Software without specific prior written permission from Apple. Except as expressly
 stated in this notice, no other rights or licenses, express or implied, are granted by Apple
 herein, including but not limited to any patent rights that may be infringed by your 
 derivative works or by other works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO WARRANTIES, 
 EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, 
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS 
 USE AND OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR CONSEQUENTIAL 
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS 
 OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, 
 REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND 
 WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR 
 OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import <Cocoa/Cocoa.h>
#import "Controller.h"
#import "Document.h"
#import "Preferences.h"

static NSString *fullPathOfAppForType(NSString *type);	// Return app to open docs of a given extension

@implementation Controller

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // To get service requests to go to the controller...
    [NSApp setServicesProvider:self];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    NSArray *windows = [app windows];
    unsigned count = [windows count];
    unsigned needsSaving = 0;
 
    // Determine if there are any unsaved documents...

    while (count--) {
        NSWindow *window = [windows objectAtIndex:count];
        Document *document = [Document documentForWindow:window];
        if (document && [document isDocumentEdited]) needsSaving++;
    }

    if (needsSaving > 0) {
        int choice = NSAlertDefaultReturn;	// Meaning, review changes
	if (needsSaving > 1) {	// If we only have 1 unsaved document, we skip the "review changes?" panel
            NSString *title = [NSString stringWithFormat:NSLocalizedString(@"You have %d documents with unsaved changes. Do you want to review these changes before quitting?", @"Title of alert panel which comes up when user chooses Quit and there are multiple unsaved documents."), needsSaving];
	    choice = NSRunAlertPanel(title, 
			NSLocalizedString(@"If you don\\U2019t review your documents, all your changes will be lost.", @"Warning in the alert panel which comes up when user chooses Quit and there are unsaved documents."), 
			NSLocalizedString(@"Review Changes\\U2026", @"Choice (on a button) given to user which allows him/her to review all unsaved documents if he/she quits the application without saving them all first."), 	// ellipses
			NSLocalizedString(@"Discard Changes", @"Choice (on a button) given to user which allows him/her to quit the application even though there are unsaved documents."), 
			NSLocalizedString(@"Cancel", @"Button choice allowing user to cancel."));
	    if (choice == NSAlertOtherReturn) return NSTerminateCancel;       	/* Cancel */
        }
	if (choice == NSAlertDefaultReturn) {	/* Review unsaved; Quit Anyway falls through */
            
            [Document reviewChangesAndQuitEnumeration:YES];
            return NSTerminateLater;
        }
    }
    
    return NSTerminateNow;
}


- (void)applicationWillTerminate:(NSNotification *)notification {
    [Preferences saveDefaults];
}


- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    // Now for a unfortunate hack to see if we're being force-fed screen grabs from 9, which have SimpleText's
    // app signature... If the file has type PICT and creator ttxt, we should open it in an image viewer.
    // Note that this diversion is an issue only for TextEdit, which duplicates SimpleText's app signature.
    NSDictionary *attributes = [[NSFileManager defaultManager] fileAttributesAtPath:filename traverseLink:YES];
    if (attributes && ([attributes fileHFSTypeCode] == 'PICT') && ([attributes fileHFSCreatorCode] == 'ttxt')) {
        NSString *app = fullPathOfAppForType(@"pict");
        // If we get back ourselves (TextEdit) or nothing, hardwire to use Preview
        if (!app || [app isEqual:[[NSBundle mainBundle] bundlePath]]) app = [[NSWorkspace sharedWorkspace] fullPathForApplication:@"Preview"];
        if (app) return [[NSWorkspace sharedWorkspace] openFile:filename withApplication:app];
    }
    
    if ([Document openDocumentWithPath:filename encoding:[[Preferences objectForKey:PlainTextEncodingForRead] intValue]]) {
        return YES;
    } else {
	// We delay the alerts so we put up one panel for more than one failure. The openFailures array determines whether there are any queued up filenames not displayed yet. If we had a "openMultipleFilenames" delegate method for NSApplication, this wouldn't be needed.
	if (!openFailures) openFailures = [[NSMutableArray alloc] init];
	[openFailures addObject:filename];
	if ([openFailures count] == 1) [self performSelector:@selector(indicateOpenFailure:) withObject:nil afterDelay:0.0];
	return NO;
   }
}

- (BOOL)application:(NSApplication *)sender openTempFile:(NSString *)filename {
    /* ??? Need to handle temp file better */
    return [self application:sender openFile:filename];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
    return [Document openUntitled:YES] ? YES : NO;
}

- (BOOL)application:(NSApplication *)sender printFile:(NSString *)filename {
    BOOL retval = NO;
    BOOL releaseDoc = NO;
    Document *document;

    document = [Document documentForPath:filename];
    if (!document) {
        document =  [[Document alloc] initWithPath:filename encoding:[[Preferences objectForKey:PlainTextEncodingForRead] intValue] uniqueZone:NO];
        releaseDoc = YES;
    }
    if (document) {
        BOOL useUI = [NSPrintInfo defaultPrinter] ? NO : YES;

        [document printDocumentUsingPrintPanel:useUI];
        retval = YES;

        if (releaseDoc) {
            // If we created it, we get rid of it.
            [document release];
        }
    }
    return retval;
}

- (void)createNew:(id)sender {
    (void)[Document openUntitled:NO];
}

- (void)open:(id)sender {
    [Document open:sender];
}

- (void)saveAll:(id)sender {
    [Document saveAllEnumeration:YES];
}

/* This method gets called once at the end of a series of open failures coming from Finder or other external source. Failed filenames in the meantime have been gathered in openFailures array. 
*/
- (void)indicateOpenFailure:(id)ignoredArgument {
   NSArray *array = openFailures;	// In case more filenames are processed while the modal panel is up
   openFailures = nil;
   [Document displayOpenFailureForFiles:array someSucceeded:YES title:NSLocalizedString(@"TextEdit Open Failed", @"Title of alert indicating file couldn't be opened; with application name")];	// we don't know at this point whether any did succeed, so we pass someSucceeded = YES
}


/*** Services support ***/

- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error {
    NSArray *types = [pboard types];
    NSString *filename, *origFilename;

    if ([types containsObject:NSStringPboardType] && (filename = origFilename = [pboard stringForType:NSStringPboardType])) {
        BOOL success = [Document openDocumentWithPath:filename encoding:[[Preferences objectForKey:PlainTextEncodingForRead] intValue]] ? YES : NO;
        if (!success) {	// Check to see if the user mistakenly included a carriage return or more at the end of the file name...
            filename = [[filename substringWithRange:[filename lineRangeForRange:NSMakeRange(0, 0)]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([filename hasPrefix:@"~"]) filename = [filename stringByExpandingTildeInPath];	/* Convert the "~username" case */
            if (![origFilename isEqual:filename]) success = [Document openDocumentWithPath:filename encoding:[[Preferences objectForKey:PlainTextEncodingForRead] intValue]] ? YES : NO;
        }
        // Given that this is a one-way service (no return), we need to put up the error panel ourselves and we do not set *error.
        if (!success) {
            if ([filename length] > PATH_MAX + 10) filename = [[filename substringToIndex:PATH_MAX] stringByAppendingString:@"... "];
            (void)NSRunAlertPanel(NSLocalizedString(@"Open File Failed", @"Title of alert indicating error during Open File service"), 
                    NSLocalizedString(@"Couldn\\U2019t open file %@.", @"Message indicating file couldn't be opened; %@ is the filename."), 
                    NSLocalizedString(@"OK", @"OK"), nil, nil, filename);
        }
    }
}

- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error {
    BOOL success = NO;
    Document *document = [Document openUntitled:NO];
    NSArray *types = [pboard types];
    NSString *preferredType = [[document firstTextView] preferredPasteboardTypeFromArray:types restrictedToTypesFromArray:nil];

    if (preferredType) {
	[document setRichText:![preferredType isEqualToString:NSStringPboardType]];	/* Special case to open a plain text document */
	success = [[document firstTextView] readSelectionFromPasteboard:pboard type:preferredType];
        [document setDocumentName:nil];
    }
    
    if (!success) {
        (void)NSRunAlertPanel(NSLocalizedString(@"Open Selection Failed", @"Title of alert indicating error during Open Selection service"),
                              NSLocalizedString(@"Couldn\\U2019t open selection.", @"Message indicating selection couldn't be opened during Open Selection service"),
                              NSLocalizedString(@"OK", @"OK"), nil, nil);
        // No need to report an error string...
    }
}

@end



@implementation Controller (ScriptingSupport)

// Scripting support.

- (NSArray *)orderedDocuments {
    NSArray *orderedWindows = [NSApp valueForKey:@"orderedWindows"];
    unsigned i, c = [orderedWindows count];
    NSMutableArray *orderedDocs = [NSMutableArray array];
    id curDelegate;
    
    for (i=0; i<c; i++) {
        curDelegate = [[orderedWindows objectAtIndex:i] delegate];
        
        if ((curDelegate != nil) && [curDelegate isKindOfClass:[Document class]]) {
            [orderedDocs addObject:curDelegate];
        }
    }
    return orderedDocs;
}

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key {
    return [key isEqualToString:@"orderedDocuments"];
}

- (void)insertInOrderedDocuments:(Document *)doc atIndex:(int)index {
    [doc retain];	// Keep it around...
    [[doc firstTextView] setSelectedRange:NSMakeRange(0, 0)];
    [doc setDocumentName:nil];
    [doc setDocumentEdited:NO];
    [[doc window] makeKeyAndOrderFront:nil];
}

@end



/* A little function to find the app to open docs of a given extension. Unfortunately there isn't direct NSWorkspace API for this, so we have to create a file and see who would open it. Ugh.
*/
static NSString *fullPathOfAppForType(NSString *type) {
    NSString *appName = nil;
    NSString *tmpFileName = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingString:[@"_TextEdit" stringByAppendingPathExtension:type]]];
    if ([[NSFileManager defaultManager] createFileAtPath:tmpFileName contents:[NSData data] attributes:nil]) {
        (void)[[NSWorkspace sharedWorkspace] getInfoForFile:tmpFileName application:&appName type:NULL];
        (void)[[NSFileManager defaultManager] removeFileAtPath:tmpFileName handler:nil];
    }
    return appName;
}

