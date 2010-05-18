/*
        DocumentReadWrite.m
        Copyright (c) 1995-2003 by Apple Computer, Inc., all rights reserved.
        Author: Ali Ozer

        Code to read/write text documents.

	Some of the complexity here comes from the fact that we want to 
	preserve the original encoding of the file in order to save the file 
	correctly later on. If the user opens a Unicode file, on save, it should 
	be saved as Unicode. If the user opens a file in WinLatin1 encoding, 
	and on save it has to be changed to Unicode, we should be able to tell 
	the user this. Without these constraints, opening plain or rich files as 
	attributed strings would actually be a lot easier (and most apps can just
	go that route)...
        
        In the save routine we also have additional complexity because of the use
        of exchangedata(), which allows exchanging contents of files, which in turn
        allows preserving external information associated with files, such as
        aliases to the file, icon location, creation date, etc.
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
#import "Document.h"
#import "ScalingScrollView.h"
#import "Preferences.h"
#import <sys/stat.h>
#import <string.h>	// For memcmp()...
#import <unistd.h>	// For exchangedata()
#import <sys/param.h>	// For MAXPATHLEN


/* Implementations further below
*/
static BOOL exchangeFileContents(NSString *path1, NSString *path2, NSDictionary *path2Attrs);
static NSString *tempFileName(NSString *origName);


/* Old Edit app used to write out 12 pt paddings; we compensate for that.
*/
#define oldEditPaddingCompensation 12.0


@implementation Document(ReadWrite)

/* Loads from the specified path, sets encoding and textStorage. Note that if the file looks like RTF or RTFD, this method will open the file in rich text mode, regardless of the setting of encoding.
*/
- (BOOL)loadFromPath:(NSString *)fileName encoding:(unsigned)encoding ignoreRTF:(BOOL)ignoreRTF ignoreHTML:(BOOL)ignoreHTML {
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSDictionary *docAttrs;
    NSTextStorage *text = [self textStorage];
    NSLayoutManager *layoutManager = [self layoutManager];
    NSURL *url = [NSURL fileURLWithPath:fileName];
    NSString *docType;
    id val, viewSizeVal, paperSizeVal;
    NSDate *modDate;
    
    // Set up the options dictionary with desired parameters
    [options setObject:url forKey:@"BaseURL"];
    if (encoding < SmallestCustomStringEncoding) [options setObject:[NSNumber numberWithUnsignedInt:encoding] forKey:@"CharacterEncoding"];

    // Check extensions to see if we should load the document as plain. Note that this check isn't always conclusive,
    // which is why we do another check below, after the document has been loaded (and correctly categorized).
    if (ignoreRTF || ignoreHTML) {
	NSString *extension = [[fileName pathExtension] lowercaseString];
	if ((ignoreRTF && [extension isEqual:@"rtf"]) || (ignoreHTML && ([extension isEqual:@"htm"] || [extension isEqual:@"html"]))) {
	    [options setObject:NSPlainTextDocumentType forKey:@"DocumentType"];		// Force plain
	}
    }

    [[text mutableString] setString:@""];	// Empty the document
    [self setRichText:YES];			// Assume rich...
    
    modDate = [[[NSFileManager defaultManager] fileAttributesAtPath:fileName traverseLink:YES] fileModificationDate];

    while (TRUE) {		// We actually run through this once or twice, no more
        BOOL success;
        
        [layoutManager retain];			// Temporarily remove layout manager so it doesn't do any work while loading
        [text removeLayoutManager:layoutManager];
        [text beginEditing];			// Bracket with begin/end editing for efficiency
        success = [text readFromURL:url options:options documentAttributes:&docAttrs];	// Read!
        [text endEditing];
        [text addLayoutManager:layoutManager];	// Hook layout manager back up
        [layoutManager release];

        if (!success) return NO;
        
        docType = [docAttrs objectForKey:@"DocumentType"];		// Check what we actually read

        // If the document turns out to be rich after all (we can't always tell, reload it, this time as plain for sure).
        if (![[options objectForKey:@"DocumentType"] isEqualToString:NSPlainTextDocumentType] && 
             ((ignoreHTML && [docType isEqual:NSHTMLTextDocumentType]) || 
              (ignoreRTF && ([docType isEqual:NSRTFTextDocumentType] || [docType isEqual:NSRTFDTextDocumentType])))) {
            [[text mutableString] setString:@""];	// Empty the document, and reload
            [options setObject:NSPlainTextDocumentType forKey:@"DocumentType"];
        } else {
            break;
        }
    };
    
    if ([docType isEqual:NSRTFTextDocumentType]) encoding = RichTextStringEncoding;
    else if ([docType isEqual:NSRTFDTextDocumentType]) encoding = RichTextWithGraphicsStringEncoding;
    else if ([docType isEqual:NSHTMLTextDocumentType]) encoding = HTMLStringEncoding;
    else if ([docType isEqual:NSDocFormatTextDocumentType]) encoding = DocStringEncoding;
    else if ([docType isEqual:NSMacSimpleTextDocumentType]) encoding = SimpleTextStringEncoding;
    else if ([docType isEqual:NSPlainTextDocumentType]) {
	val = [docAttrs objectForKey:@"CharacterEncoding"];
	encoding = val ? [val unsignedIntValue] : UnknownStringEncoding;
	[self setRichText:NO dealWithAttachments:NO];
    } else {
	encoding = UnknownStringEncoding;
    }

    [self setEncoding:encoding];

    if (val = [docAttrs objectForKey:@"Converted"]) {
        [self setConverted:([val intValue] > 0)];	// Indicates filtered
        [self setLossy:([val intValue] < 0)];		// Indicates lossily loaded
    }
    
    if ((val = [docAttrs objectForKey:@"ViewMode"]) && ([val intValue] == 1)) {
        [self setHasMultiplePages:YES];	// Page layout view
        if ((val = [docAttrs objectForKey:@"ViewZoom"])) {
            float zoom = [val floatValue];
            [scrollView setScaleFactor:(zoom / 100.0) adjustPopup:YES];
        }
    } else {
	[self setHasMultiplePages:NO];	// Normal view
    }

    if ((val = [docAttrs objectForKey:@"LeftMargin"])) [[self printInfo] setLeftMargin:[val floatValue]];
    if ((val = [docAttrs objectForKey:@"RightMargin"])) [[self printInfo] setRightMargin:[val floatValue]];
    if ((val = [docAttrs objectForKey:@"BottomMargin"])) [[self printInfo] setBottomMargin:[val floatValue]];
    if ((val = [docAttrs objectForKey:@"TopMargin"])) [[self printInfo] setTopMargin:[val floatValue]];
    [self printInfoUpdated];
    
    // Pre MacOSX versions of TextEdit wrote out the view (window) size in PaperSize
    // If we encounter a non-MacOSX RTF file, and it's written by TextEdit, use PaperSize as ViewSize
    
    viewSizeVal = [docAttrs objectForKey:@"ViewSize"];
    paperSizeVal = [docAttrs objectForKey:@"PaperSize"];
    if (paperSizeVal && NSEqualSizes([paperSizeVal sizeValue], NSZeroSize)) paperSizeVal = nil;	// Protect against some old documents with 0 paper size
    
    if (viewSizeVal) {
        [self setViewSize:[viewSizeVal sizeValue]];
        if (paperSizeVal) [self setPaperSize:[paperSizeVal sizeValue]];
    } else {	// No ViewSize...
        if (paperSizeVal) {	// See if PaperSize should be used as ViewSize; if so, we also have some tweaking to do on it
            val = [docAttrs objectForKey:@"CocoaRTFVersion"];
            if (val && ([val intValue] < 100)) {	// Indicates old RTF file; value described in AppKit/NSAttributedString.h
                NSSize size = [paperSizeVal sizeValue];
                if (size.width > 0 && size.height > 0 && ![self hasMultiplePages]) {
                    size.width = size.width - oldEditPaddingCompensation;
                    [self setViewSize:size];
                }
            } else {
               [self setPaperSize:[paperSizeVal sizeValue]];
            }
        }
    }

    if ((val = [docAttrs objectForKey:@"HyphenationFactor"])) [self setHyphenationFactor:[val floatValue]];
    if ((val = [docAttrs objectForKey:@"BackgroundColor"])) [self setBackgroundColor:val];
    [self setReadOnly:((val = [docAttrs objectForKey:@"ReadOnly"]) && ([val intValue] > 0))];

    [self setFileModDate:modDate];
    
    return YES;
}

- (SaveStatus)saveToPath:(NSString *)fileName encoding:(unsigned)encoding updateFilenames:(BOOL)updateFileNamesFlag overwriteOK:(BOOL)overwrite hideExtension:(FileExtensionStatus)extensionStatus {
    BOOL success = NO;
    NSString *intermediateFileNameToSave;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *actualFileNameToSave = [fileName stringByResolvingSymlinksInPath];	/* Follow links to save */
    NSDictionary *curAttributes = [fileManager fileAttributesAtPath:actualFileNameToSave traverseLink:YES];
    NSMutableDictionary *newAttributes;

    
    /* Check to see if file seems writable */
    if (curAttributes) {	/* File exists; if it is not writable and we were not asked to overwrite, then punt... */
        if (!overwrite && ![fileManager isWritableFileAtPath:actualFileNameToSave]) return SaveStatusFileNotWritable;
	if (!overwrite && [actualFileNameToSave isEqual:[self documentName]] && [self isEditedExternally:[curAttributes fileModificationDate]]) return SaveStatusFileEditedExternally;
    } else {	/* File doesn't exist; if the enclosing folder is not writable then punt */
        if (![fileManager isWritableFileAtPath:[actualFileNameToSave stringByDeletingLastPathComponent]]) return SaveStatusDestinationNotWritable;
    }

    /* Determine name of intermediate file */
    if (curAttributes) {	// File exists, so use an intermediate file
        // Make up a unique name in the destination folder by prepending a prefix to the desired file name
        intermediateFileNameToSave = tempFileName(actualFileNameToSave);
    } else {	// No existing file, just write the final destination
        intermediateFileNameToSave = actualFileNameToSave;
    }
    
    /* Now actually write the file */
    if (encoding == RichTextWithGraphicsStringEncoding || encoding == RichTextStringEncoding || encoding == DocStringEncoding) {
	NSRange range = NSMakeRange(0, [[self textStorage] length]);
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSValue valueWithSize:[self viewSize]], @"ViewSize", 
            [NSValue valueWithSize:[self paperSize]], @"PaperSize", 
            [NSNumber numberWithInt:[self isReadOnly] ? 1 : 0], @"ReadOnly", 
            [NSNumber numberWithFloat:[self hyphenationFactor]], @"HyphenationFactor", 
            [NSNumber numberWithFloat:[[self printInfo] leftMargin]], @"LeftMargin", 
            [NSNumber numberWithFloat:[[self printInfo] rightMargin]], @"RightMargin", 
            [NSNumber numberWithFloat:[[self printInfo] bottomMargin]], @"BottomMargin", 
            [NSNumber numberWithFloat:[[self printInfo] topMargin]], @"TopMargin", 
            [NSNumber numberWithInt:[self hasMultiplePages] ? 1 : 0], @"ViewMode",
            nil];
        if ([self hasMultiplePages]) [dict setObject:[NSNumber numberWithFloat:[scrollView scaleFactor] * 100.0] forKey:@"ViewZoom"];
        if ([self backgroundColor]) [dict setObject:[self backgroundColor] forKey:@"BackgroundColor"];
	if (encoding == RichTextWithGraphicsStringEncoding) {
            NSFileWrapper *wrapper = [[self textStorage] RTFDFileWrapperFromRange:range documentAttributes:dict];
	    success = wrapper ? [wrapper writeToFile:intermediateFileNameToSave atomically:YES updateFilenames:updateFileNamesFlag] : NO;
	} else if (encoding == RichTextStringEncoding) {
            NSData *data = [[self textStorage] RTFFromRange:range documentAttributes:dict];
	    success = data ? [data writeToFile:intermediateFileNameToSave atomically:YES] : NO;
	} else if (encoding == DocStringEncoding) {
            NSData *data = [[self textStorage] docFormatFromRange:range documentAttributes:dict];
	    success = data ? [data writeToFile:intermediateFileNameToSave atomically:YES] : NO;
        }

    } else {
        NSData *data = [[textStorage string] dataUsingEncoding:encoding];
        if (!data) return SaveStatusEncodingNotApplicable;
        success = [data writeToFile:intermediateFileNameToSave atomically:YES];
    }

    if (!success) return SaveStatusNotOK;
    
    /* At this point we have written the data out.  Now for the paperwork.
       If there was no previous file, then we just need to set some attributes (see further below).
       If there was an existing file, we need to:
            Exchange the intermediate and actual file (so the original file's attributes are preserved)
            If exchange succeeds:
                If backup is desired, rename the intermediate to backup file name; otherwise delete it
            If exchange fails:
                If backup is desired, rename the original to backup file name
                Rename the intermediate to actual file name
    */
    if (curAttributes) {	// This indicates there was an existing file...
        BOOL backupDesired = ![[Preferences objectForKey:DeleteBackup] boolValue];
        BOOL thereIsABackup;
        // First create the backup file name: basename~.extension, or basename~, or .extension~
        NSString *backupFileName = [actualFileNameToSave stringByDeletingPathExtension]; // Temporary state, holding name without extension
        NSString *extension = [actualFileNameToSave pathExtension];
        if (![backupFileName isEqualToString:@""] && ![extension isEqualToString:@""]) {
            backupFileName = [[backupFileName stringByAppendingString:@"~"] stringByAppendingPathExtension:extension];
        } else {
            backupFileName = [actualFileNameToSave stringByAppendingString:@"~"];
        }
        thereIsABackup = [fileManager fileExistsAtPath:backupFileName];
        
        if (exchangeFileContents(intermediateFileNameToSave, actualFileNameToSave, curAttributes)) {
            // Exchange worked; at this point the document is saved under actualFileNameToSave; previous contents are in intermediateFileNameToSave
            if (backupDesired) {
                if (thereIsABackup && exchangeFileContents(intermediateFileNameToSave, backupFileName, nil)) {	// If there is an existing backup, attempt exchange
                    // If exchange worked, manually copy the attributes over and remove the 2nd generation backup (which is now in intermediateFileNameToSave)
                    (void)[fileManager changeFileAttributes:curAttributes atPath:backupFileName];
                    (void)[fileManager removeFileAtPath:intermediateFileNameToSave handler:nil];
                } else {
                    if (thereIsABackup) (void)[fileManager removeFileAtPath:backupFileName handler:nil];
                    if ([fileManager movePath:intermediateFileNameToSave toPath:backupFileName handler:nil]) {
                        (void)[fileManager changeFileAttributes:curAttributes atPath:backupFileName];
                    } else {	// For some reason, could not generate backup; delete intermediate
                        (void)[fileManager removeFileAtPath:intermediateFileNameToSave handler:nil];
                    }
                }
            } else {	// No backup desired; delete the intermediate. But leave around any existing older backup
                (void)[fileManager removeFileAtPath:intermediateFileNameToSave handler:nil];
            }
        } else {	// Exchange did not work, do the file exchange by moving stuff around
            if (thereIsABackup) (void)[fileManager removeFileAtPath:backupFileName handler:nil];	// Remove old backup
            // Now move old file to backup; if this fails, we should give up as something is wrong and we don't want to lose the backup
            success = [fileManager movePath:actualFileNameToSave toPath:backupFileName handler:nil];
            if (success) {
                // And move intermediate to actual file; but if that fails, restore the backup as actual
                success = [fileManager movePath:intermediateFileNameToSave toPath:actualFileNameToSave handler:nil];
                if (success) {	
                    if (!backupDesired) (void)[fileManager removeFileAtPath:backupFileName handler:nil];	// Delete unwanted backup
                } else if ([fileManager movePath:backupFileName toPath:actualFileNameToSave handler:nil]) {	// Restore backup
                    (void)[fileManager removeFileAtPath:intermediateFileNameToSave handler:nil];	// Clean intermediate
                }
            }
        }

	if (!success) return SaveStatusNotOK;
    }
    

    /* Now we set attributes and such on the destination file, as needed. We could be a little more sophisticated here and only do some stuff based on whether the exchange operation worked or not.
    */
    newAttributes = [NSMutableDictionary dictionary];
    if (curAttributes) {	// Existing file
        BOOL saveFilesWritable = [[Preferences objectForKey:SaveFilesWritable] boolValue];
        id permissions = [curAttributes objectForKey:NSFilePosixPermissions];
        if (permissions) {
            if (saveFilesWritable) permissions = [NSNumber numberWithUnsignedLong:([permissions unsignedLongValue] | 0200)];
            [newAttributes setObject:permissions forKey:NSFilePosixPermissions];
        }
        // !!! This does not make the file immutable on file systems w/out exchange; probably should do that though
        if (saveFilesWritable && [curAttributes fileIsImmutable]) [newAttributes setObject:[NSNumber numberWithBool:NO] forKey:NSFileImmutable];
        // Preserve previous state of hidden extension bit
        if (extensionStatus == FileExtensionPreviousState) {
            id hiddenExtension = [curAttributes objectForKey:NSFileExtensionHidden];
            if (hiddenExtension) extensionStatus = [hiddenExtension boolValue] ? FileExtensionHidden : FileExtensionShown ;
        }
        // Set hidden extension bit
        [newAttributes setObject:[NSNumber numberWithBool:(extensionStatus != FileExtensionShown)] forKey:NSFileExtensionHidden];
        // We need to clear previous type/creator out as it might not apply at all to the new document
        if ([curAttributes fileHFSCreatorCode] != 0) [newAttributes setObject:[NSNumber numberWithUnsignedInt:0] forKey:NSFileHFSCreatorCode];
        if ([curAttributes fileHFSTypeCode] != 0) [newAttributes setObject:[NSNumber numberWithUnsignedInt:0] forKey:NSFileHFSTypeCode];
    } else {	// New file
        // Set hidden extension bit to YES if desired; otherwise don't do anything (as NO is the default)
        if (extensionStatus != FileExtensionShown) [newAttributes setObject:[NSNumber numberWithBool:YES] forKey:NSFileExtensionHidden];
    }
    
    if ([newAttributes count] > 0) (void)[fileManager changeFileAttributes:newAttributes atPath:actualFileNameToSave];

    // Refresh the file attrs (if for some reason not available, will become nil, which is fine, as it indicates "not known")
    [self setFileModDate:[[fileManager fileAttributesAtPath:actualFileNameToSave traverseLink:YES] fileModificationDate]];

    return SaveStatusOK;
}

@end



/* Exchange the contents of the two specified files. First file is assumed to be new (and writable); second file will be temporarily made writable to allow the exchange. The attributes are those of the second file; if nil, they will be computed on the fly.
*/
static BOOL exchangeFileContents(NSString *path1, NSString *path2, NSDictionary *path2Attrs) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    char cPath1[MAXPATHLEN+1];
    char cPath2[MAXPATHLEN+1];
    int err;
    
    if (![path1 getFileSystemRepresentation:cPath1 maxLength:MAXPATHLEN] || ![path2 getFileSystemRepresentation:cPath2 maxLength:MAXPATHLEN]) return NO;

    err = exchangedata(cPath1, cPath2, 0) ? errno : 0;

    if (err == EACCES || err == EPERM) {	// Seems to be a write-protected or locked file; try temporarily changing
        NSDictionary *attrs = path2Attrs ? path2Attrs : [fileManager fileAttributesAtPath:path2 traverseLink:YES];
        NSNumber *curPerms = [attrs objectForKey:NSFilePosixPermissions];
        BOOL curImmutable = [attrs fileIsImmutable];
        if (curPerms) [fileManager changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:[curPerms unsignedLongValue] | 0200], NSFilePosixPermissions, nil] atPath:path2];
        if (curImmutable) [fileManager changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], NSFileImmutable, nil] atPath:path2];
	err = exchangedata(cPath1, cPath2, 0) ? errno : 0;
        // Restore original values
	if (curPerms) [fileManager changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:curPerms, NSFilePosixPermissions, nil] atPath:path2];
        if (curImmutable) [fileManager changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSFileImmutable, nil] atPath:path2];
    }
    
    return err ? NO : YES;
}


/* Generate a reasonably short temporary unique file, given an original path.
*/
static NSString *tempFileName(NSString *origPath) {
    static int sequenceNumber = 0;
    NSString *name;
    do {
        sequenceNumber++;
        name = [NSString stringWithFormat:@"%d-%d-%d.%@", [[NSProcessInfo processInfo] processIdentifier], (int)[NSDate timeIntervalSinceReferenceDate], sequenceNumber, [origPath pathExtension]];
        name = [[origPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
    } while ([[NSFileManager defaultManager] fileExistsAtPath:name]);
    return name;
}



