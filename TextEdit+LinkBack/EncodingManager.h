#import <Foundation/Foundation.h>

enum {
    NoStringEncoding = 0xFFFFFFFF
};


@interface EncodingPopUpButton : NSPopUpButton {
    NSStringEncoding defaultEncoding;
    BOOL hasDefaultEntry;
}
- (void)setEncoding:(NSStringEncoding)encoding defaultEntry:(BOOL)flag;
@end


    
@interface EncodingManager : NSObject {
    @private
    IBOutlet NSMatrix *encodingMatrix;
    NSArray *encodings;

    // These three outlets are temporary, reset each time the encodingAccessory nib is loaded, and cleared each time
    IBOutlet NSButton *ignoreRichTextButton;
    IBOutlet EncodingPopUpButton *encodingPopupButton;
    IBOutlet NSView *encodingAccessory;
}

/* There is just one instance...
*/
+ (EncodingManager *)sharedInstance;

/* List of encodings that should be shown in encoding lists
*/
- (NSArray *)enabledEncodings;

/* Returns a fresh encoding accessory to be used in open/save panels. Also returns pointers to the encoding popup and ignore rich text button if desired.
*/
- (NSView *)encodingAccessory:(unsigned)encoding includeDefaultEntry:(BOOL)includeDefaultItem enableIgnoreRichTextButton:(BOOL)includeRichTextButton encodingPopUp:(NSPopUpButton **)popup ignoreRichTextButton:(NSButton **)button;

/* Empties then initializes the supplied popup with the supported encodings.
*/
- (void)setupPopUp:(NSPopUpButton *)button selectedEncoding:(unsigned)selectedEncoding withDefaultEntry:(BOOL)flag;

/* Action methods for bringing up and dealing with changes in the encodings list panel
*/
- (IBAction)showPanel:(id)sender;
- (IBAction)encodingListChanged:(id)sender;
- (IBAction)clearAll:(id)sender;
- (IBAction)selectAll:(id)sender;
- (IBAction)revertToDefault:(id)sender;
    
/* Internal method to save and communicate changes to the encoding list
*/
- (void)noteEncodingListChange:(BOOL)writeDefault updateList:(BOOL)updateList postNotification:(BOOL)post;


@end
