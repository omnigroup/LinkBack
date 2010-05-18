/*
        Preferences.m
        Copyright (c) 1995-2003 by Apple Computer, Inc., all rights reserved.
        Author: Ali Ozer

        Preferences controller. To add new defaults search for one
        of the existing keys. Some keys have UI, others don't; 
        use one similar to the one you're adding.

        displayedValues is a mirror of the UI. These are committed by copying
        these values to curValues.

        This module allows for UI where there is or there isn't an OK button. 
        If you wish to have an OK button, connect OK to ok:,
        Revert to revert:, and don't call commitDisplayedValues from the 
        various action messages. 
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
#import "Preferences.h"
#import "EncodingManager.h"

static NSDictionary *defaultValues() {
    static NSDictionary *dict = nil;
    if (!dict) {
        dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                [NSNumber numberWithBool:YES], DeleteBackup, 
                [NSNumber numberWithBool:NO], SaveFilesWritable, 
                [NSNumber numberWithBool:NO], OverwriteReadOnlyFiles, 
                [NSNumber numberWithBool:YES], RichText, 
                [NSNumber numberWithBool:NO], ShowPageBreaks,
		[NSNumber numberWithBool:NO], OpenPanelFollowsMainWindow,
		[NSNumber numberWithBool:YES], AddExtensionToNewPlainTextFiles,
                [NSNumber numberWithInt:75], WindowWidth, 
                [NSNumber numberWithInt:25], WindowHeight, 
                [NSNumber numberWithInt:NoStringEncoding], PlainTextEncodingForRead,
                [NSNumber numberWithInt:NoStringEncoding], PlainTextEncodingForWrite,
		[NSNumber numberWithInt:8], TabWidth,
		[NSNumber numberWithInt:100000], ForegroundLayoutToIndex,       
                [NSFont userFixedPitchFontOfSize:0.0], PlainTextFont, 
                [NSFont userFontOfSize:0.0], RichTextFont, 
                [NSNumber numberWithBool:NO], IgnoreRichText,
		[NSNumber numberWithBool:NO], IgnoreHTML,
                [NSNumber numberWithBool:YES], CheckSpellingAsYouType,
                [NSNumber numberWithBool:YES], ShowRuler,
		nil];
    }
    return dict;
}

@implementation Preferences

static Preferences *sharedInstance = nil;

+ (Preferences *)sharedInstance {
    return sharedInstance ? sharedInstance : [[self alloc] init];
}

- (id)init {
    if (sharedInstance) {		// We just have one instance of the Preferences class, return that one instead
        [self release];
    } else if (self = [super init]) {
        curValues = [[[self class] preferencesFromDefaults] copyWithZone:[self zone]];
        origValues = [curValues retain];
        [self discardDisplayedValues];
        sharedInstance = self;
    }
    return sharedInstance;
}

- (void)dealloc {
    if (self != sharedInstance) [super dealloc];	// Don't free the shared instance
}


/* The next few factory methods are conveniences, working on the shared instance
*/
+ (id)objectForKey:(id)key {
    return [[[self sharedInstance] preferences] objectForKey:key];
}

+ (void)saveDefaults {
    [[self sharedInstance] saveDefaults];
}

- (void)saveDefaults {
    NSDictionary *prefs = [self preferences];
    if (![origValues isEqual:prefs]) [Preferences savePreferencesToDefaults:prefs];
}

- (NSDictionary *)preferences {
    return curValues;
}

- (void)showPanel:(id)sender {
    if (!richTextFontNameField) {
        if (![NSBundle loadNibNamed:@"Preferences" owner:self])  {
            NSLog(@"Failed to load Preferences.nib");
            NSBeep();
            return;
        }
	[[richTextFontNameField window] setExcludedFromWindowsMenu:YES];
	[[richTextFontNameField window] setMenu:nil];
        [self updateUI];
        [[richTextFontNameField window] center];
    }
    [[richTextFontNameField window] makeKeyAndOrderFront:nil];
}

static void showFontInField(NSFont *font, NSTextField *field) {
    [field setStringValue:font ? [NSString stringWithFormat:@"%@ %g", [font fontName], [font pointSize]] : @""];
}

- (void)updateUI {
    if (!richTextFontNameField) return;	/* UI hasn't been loaded... */

    showFontInField([displayedValues objectForKey:RichTextFont], richTextFontNameField);
    showFontInField([displayedValues objectForKey:PlainTextFont], plainTextFontNameField);

    [deleteBackupButton setState:[[displayedValues objectForKey:DeleteBackup] boolValue] ? 1 : 0];
    [saveFilesWritableButton setState:[[displayedValues objectForKey:SaveFilesWritable] boolValue]];
    [overwriteReadOnlyFilesButton setState:[[displayedValues objectForKey:OverwriteReadOnlyFiles] boolValue]];
    [addExtensionToNewPlainTextFilesButton setState:[[displayedValues objectForKey:AddExtensionToNewPlainTextFiles] boolValue]];
    [richTextMatrix selectCellWithTag:[[displayedValues objectForKey:RichText] boolValue] ? 1 : 0];
    [showPageBreaksButton setState:[[displayedValues objectForKey:ShowPageBreaks] boolValue]];
    [ignoreRichTextButton setState:[[displayedValues objectForKey:IgnoreRichText] boolValue]];
    [ignoreHTMLButton setState:[[displayedValues objectForKey:IgnoreHTML] boolValue]];
    [checkSpellingAsYouTypeButton setState:[[displayedValues objectForKey:CheckSpellingAsYouType] boolValue]];
    [showRulerButton setState:[[displayedValues objectForKey:ShowRuler] boolValue]];

    [windowWidthField setIntValue:[[displayedValues objectForKey:WindowWidth] intValue]];
    [windowHeightField setIntValue:[[displayedValues objectForKey:WindowHeight] intValue]];

    [(EncodingPopUpButton *)plainTextEncodingForReadPopup setEncoding:[[displayedValues objectForKey:PlainTextEncodingForRead] intValue] defaultEntry:YES];
    [(EncodingPopUpButton *)plainTextEncodingForWritePopup setEncoding:[[displayedValues objectForKey:PlainTextEncodingForWrite] intValue] defaultEntry:YES];
}

/* Gets everything from UI except for fonts...
*/
- (void)miscChanged:(id)sender {
    static NSNumber *yes = nil;
    static NSNumber *no = nil;
    int anInt;
    
    if (!yes) {
        yes = [[NSNumber alloc] initWithBool:YES];
        no = [[NSNumber alloc] initWithBool:NO];
    }

    [displayedValues setObject:[deleteBackupButton state] ? yes : no forKey:DeleteBackup];
    [displayedValues setObject:[[richTextMatrix selectedCell] tag] ? yes : no forKey:RichText];
    [displayedValues setObject:[saveFilesWritableButton state] ? yes : no forKey:SaveFilesWritable];
    [displayedValues setObject:[overwriteReadOnlyFilesButton state] ? yes : no forKey:OverwriteReadOnlyFiles];
    [displayedValues setObject:[addExtensionToNewPlainTextFilesButton state] ? yes : no forKey:AddExtensionToNewPlainTextFiles];
    [displayedValues setObject:[showPageBreaksButton state] ? yes : no forKey:ShowPageBreaks];
    [displayedValues setObject:[NSNumber numberWithInt:[[plainTextEncodingForReadPopup selectedItem] tag]] forKey:PlainTextEncodingForRead];
    [displayedValues setObject:[NSNumber numberWithInt:[[plainTextEncodingForWritePopup selectedItem] tag]] forKey:PlainTextEncodingForWrite];
    [displayedValues setObject:[ignoreRichTextButton state] ? yes : no forKey:IgnoreRichText];
    [displayedValues setObject:[ignoreHTMLButton state] ? yes : no forKey:IgnoreHTML];
    [displayedValues setObject:[checkSpellingAsYouTypeButton state] ? yes : no forKey:CheckSpellingAsYouType];
    [displayedValues setObject:[showRulerButton state] ? yes : no forKey:ShowRuler];

    if ((anInt = [windowWidthField intValue]) < 1 || anInt > 10000) {
        if ((anInt = [[displayedValues objectForKey:WindowWidth] intValue]) < 1 || anInt > 10000) anInt = [[defaultValues() objectForKey:WindowWidth] intValue];
	[windowWidthField setIntValue:anInt];
    } else {
	[displayedValues setObject:[NSNumber numberWithInt:anInt] forKey:WindowWidth];
    }

    if ((anInt = [windowHeightField intValue]) < 1 || anInt > 10000) {
        if ((anInt = [[displayedValues objectForKey:WindowHeight] intValue]) < 1 || anInt > 10000) anInt = [[defaultValues() objectForKey:WindowHeight] intValue];
        [windowHeightField setIntValue:[[displayedValues objectForKey:WindowHeight] intValue]];
    } else {
	[displayedValues setObject:[NSNumber numberWithInt:anInt] forKey:WindowHeight];
    }

    [self commitDisplayedValues];
}

/**** Font changing code ****/

static BOOL changingRTFFont = NO;

- (void)changeRichTextFont:(id)sender {
    changingRTFFont = YES;
    [[richTextFontNameField window] makeFirstResponder:[richTextFontNameField window]];
    [[NSFontManager sharedFontManager] setSelectedFont:[curValues objectForKey:RichTextFont] isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (void)changePlainTextFont:(id)sender {
    changingRTFFont = NO;
    [[richTextFontNameField window] makeFirstResponder:[richTextFontNameField window]];
    [[NSFontManager sharedFontManager] setSelectedFont:[curValues objectForKey:PlainTextFont] isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (void)changeFont:(id)fontManager {
    if (changingRTFFont) {
        [displayedValues setObject:[fontManager convertFont:[curValues objectForKey:RichTextFont]] forKey:RichTextFont];
        showFontInField([displayedValues objectForKey:RichTextFont], richTextFontNameField);
    } else {
        [displayedValues setObject:[fontManager convertFont:[curValues objectForKey:PlainTextFont]] forKey:PlainTextFont];
        showFontInField([displayedValues objectForKey:PlainTextFont], plainTextFontNameField);
    }
    [self commitDisplayedValues];
}

/**** Commit/revert etc ****/

- (void)commitDisplayedValues {
    if (curValues != displayedValues) {
        [curValues release];
        curValues = [displayedValues copyWithZone:[self zone]];
    }
}

- (void)discardDisplayedValues {
    if (curValues != displayedValues) {
        [displayedValues release];
        displayedValues = [curValues mutableCopyWithZone:[self zone]];
        [self updateUI];
    }
}

- (void)ok:(id)sender {
    [self commitDisplayedValues];
}

- (void)revertToDefault:(id)sender {
    curValues = [defaultValues() copyWithZone:[self zone]];
    [self discardDisplayedValues];
}

- (void)revert:(id)sender {
    [self discardDisplayedValues];
}

/**** Code to deal with defaults ****/
   
#define getBoolDefault(name) \
  {id obj = [defaults objectForKey:name]; \
      [dict setObject:obj ? [NSNumber numberWithBool:[defaults boolForKey:name]] : [defaultValues() objectForKey:name] forKey:name];}

#define getIntDefault(name) \
  {id obj = [defaults objectForKey:name]; \
      [dict setObject:obj ? [NSNumber numberWithInt:[defaults integerForKey:name]] : [defaultValues() objectForKey:name] forKey:name];}

+ (NSDictionary *)preferencesFromDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:10];

    getBoolDefault(RichText);
    getBoolDefault(DeleteBackup);
    getBoolDefault(ShowPageBreaks);
    getBoolDefault(SaveFilesWritable);
    getBoolDefault(OverwriteReadOnlyFiles);
    getBoolDefault(OpenPanelFollowsMainWindow);
    getBoolDefault(AddExtensionToNewPlainTextFiles);
    getIntDefault(WindowWidth);
    getIntDefault(WindowHeight);
    getIntDefault(PlainTextEncodingForRead);
    getIntDefault(PlainTextEncodingForWrite);
    getIntDefault(TabWidth);
    getIntDefault(ForegroundLayoutToIndex);
    getBoolDefault(IgnoreRichText);
    getBoolDefault(IgnoreHTML);
    getBoolDefault(CheckSpellingAsYouType);
    getBoolDefault(ShowRuler);
    [dict setObject:[NSFont userFontOfSize:0.0] forKey:RichTextFont];
    [dict setObject:[NSFont userFixedPitchFontOfSize:0.0] forKey:PlainTextFont];

    return dict;
}

#define setBoolDefault(name) \
  {if ([[defaultValues() objectForKey:name] isEqual:[dict objectForKey:name]]) [defaults removeObjectForKey:name]; else [defaults setBool:[[dict objectForKey:name] boolValue] forKey:name];}

#define setIntDefault(name) \
  {if ([[defaultValues() objectForKey:name] isEqual:[dict objectForKey:name]]) [defaults removeObjectForKey:name]; else [defaults setInteger:[[dict objectForKey:name] intValue] forKey:name];}

+ (void)savePreferencesToDefaults:(NSDictionary *)dict {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    setBoolDefault(RichText);
    setBoolDefault(DeleteBackup);
    setBoolDefault(ShowPageBreaks);
    setBoolDefault(SaveFilesWritable);
    setBoolDefault(OverwriteReadOnlyFiles);
    setBoolDefault(OpenPanelFollowsMainWindow);
    setBoolDefault(AddExtensionToNewPlainTextFiles);
    setIntDefault(WindowWidth);
    setIntDefault(WindowHeight);
    setIntDefault(PlainTextEncodingForRead);
    setIntDefault(PlainTextEncodingForWrite);
    setIntDefault(TabWidth);
    setIntDefault(ForegroundLayoutToIndex);
    setBoolDefault(IgnoreRichText);
    setBoolDefault(IgnoreHTML);
    setBoolDefault(CheckSpellingAsYouType);
    setBoolDefault(ShowRuler);
    if (![[dict objectForKey:RichTextFont] isEqual:[NSFont userFontOfSize:0.0]]) [NSFont setUserFont:[dict objectForKey:RichTextFont]];
    if (![[dict objectForKey:PlainTextFont] isEqual:[NSFont userFixedPitchFontOfSize:0.0]]) [NSFont setUserFixedPitchFont:[dict objectForKey:PlainTextFont]];
}


/**** Window delegation ****/

// We do this to catch the case where the user enters a value into one of the text fields but closes the window without hitting enter or tab.

- (void)windowWillClose:(NSNotification *)notification {
    NSWindow *window = [notification object];
    (void)[window makeFirstResponder:window];
}


@end
