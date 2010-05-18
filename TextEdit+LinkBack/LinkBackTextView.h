//
//  LinkBackTextView.h
//  TextEdit
//
//  Created by Charles Jolley on Tue Jun 15 2004.
//  Copyright (c) 2004 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


// This class simply overrides the normal readSelectionFromPasteboard: method to do something special with image data attached to LinkBack.  This is not a good example of how to use LinkBack because it is not very robust, but it works for demos.
@interface LinkBackTextView : NSTextView

@end
