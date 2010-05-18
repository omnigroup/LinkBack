// SKTDrawDocument.m
// Sketch Example
//

#import "SKTDrawDocument.h"
#import "SKTDrawWindowController.h"
#import "SKTGraphic.h"
#import "SKTRenderingView.h"
#import "SKTRectangle.h"
#import "SKTCircle.h"
#import "SKTLine.h"
#import "SKTTextArea.h"
#import "SKTImage.h"
#import <LinkBack/LinkBack.h>

NSString *SKTDrawDocumentType = @"Apple Sketch Graphic Format";

@implementation SKTDrawDocument

// ...........................................................................
// LinkBack Support
// LIVELINK EDITS

- (void)closeLinkIfNeeded
{
    if (link) {
        [link setRepresentedObject: nil] ;
        [link closeLink] ;
        [link release] ;
        link = nil ;
    }
}

- (id)initWithLinkBack:(LinkBack*)aLink 
{
    if (self = [self init]) {
        link = [aLink retain] ;
        [link setRepresentedObject: self] ;
        
        // get graphics from link
        id linkBackData = [[link pasteboard] propertyListForType: LinkBackPboardType] ;
        id graphics = LinkBackGetAppData(linkBackData) ;
        graphics = [self drawDocumentDictionaryFromData: graphics] ;
        graphics = [self graphicsFromDrawDocumentDictionary: graphics] ;
        [self setGraphics: graphics] ;
        // fix up undo
        [[self undoManager] removeAllActions] ;
        [self updateChangeCount: NSChangeCleared] ;
    }
    
    return self ;
}

- (NSString*)displayName
{
    if (link) {
        NSString* sourceName = [link sourceName] ;
        NSString* ret = [NSString stringWithFormat: @"Graphics from %@", sourceName] ;
        return ret ;
    } else return [super displayName] ;
}

- (void)close
{
    [self closeLinkIfNeeded] ;
    [super close] ;
}

- (void)saveDocument:(id)sender
{
    // if this document is a live link doc, return the updated document contents to the client.  Otherwise, save like normal.
    // This code is from the copy: method in SKGraphicsView.  In a properly refactored version, this code could be shared.
    if (link) {
        NSArray *sel = [self graphics];
        if ([sel count] > 0) {
            NSPasteboard *pboard = [link pasteboard];
            id dta ;
            
            [pboard declareTypes:[NSArray arrayWithObjects:SKTDrawDocumentType, NSTIFFPboardType, NSPDFPboardType, nil] owner:nil];
            
            dta = [self drawDocumentDataForGraphics: sel] ;
            [pboard setData: dta forType:SKTDrawDocumentType];
            [pboard setData:[self TIFFRepresentationForGraphics: sel] forType:NSTIFFPboardType];
            [pboard setData:[self PDFRepresentationForGraphics: sel] forType:NSPDFPboardType];
            
            // save the pboard data for LinkBack.
            [pboard setPropertyList: MakeLinkBackData(@"sketch", dta) forType: LinkBackPboardType] ;
            
            [link sendEdit] ;
            
            // fix up undo
            [[self undoManager] removeAllActions] ;
            [self updateChangeCount: NSChangeCleared] ;
            
        } else NSBeep() ;
        
    } else [super saveDocument: sender] ;
}

// ...........................................................................
// Other Sketch functions
//

- (id)init {
    self = [super init];
    if (self) {
        _graphics = [[NSMutableArray allocWithZone:[self zone]] init];
    }
    return self;
}

- (void)dealloc {
    [self closeLinkIfNeeded] ;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_graphics release];
    
    [super dealloc];
}

- (void)makeWindowControllers {
    SKTDrawWindowController *myController = [[SKTDrawWindowController allocWithZone:[self zone]] init];
    [self addWindowController:myController];
    [myController release];
}

static NSString *SKTGraphicsListKey = @"GraphicsList";
static NSString *SKTDrawDocumentVersionKey = @"DrawDocumentVersion";
static int SKTCurrentDrawDocumentVersion = 1;
static NSString *SKTPrintInfoKey = @"PrintInfo";


- (NSDictionary *)drawDocumentDictionaryForGraphics:(NSArray *)graphics {
    NSMutableDictionary *doc = [NSMutableDictionary dictionary];
    unsigned i, c = [graphics count];
    NSMutableArray *graphicDicts = [NSMutableArray arrayWithCapacity:c];

    for (i=0; i<c; i++) {
        [graphicDicts addObject:[[graphics objectAtIndex:i] propertyListRepresentation]];
    }
    [doc setObject:graphicDicts forKey:SKTGraphicsListKey];
    [doc setObject:[NSString stringWithFormat:@"%d", SKTCurrentDrawDocumentVersion] forKey:SKTDrawDocumentVersionKey];
    [doc setObject:[NSArchiver archivedDataWithRootObject:[self printInfo]] forKey:SKTPrintInfoKey];

    return doc;
}

- (NSData *)drawDocumentDataForGraphics:(NSArray *)graphics {
    NSDictionary *doc = [self drawDocumentDictionaryForGraphics:graphics];
    NSString *string = [doc description];
    return [string dataUsingEncoding:NSASCIIStringEncoding];
}

- (NSDictionary *)drawDocumentDictionaryFromData:(NSData *)data {
    NSString *string = [[NSString allocWithZone:[self zone]] initWithData:data encoding:NSASCIIStringEncoding];
    NSDictionary *doc = [string propertyList];
    
    [string release];

    return doc;
}

- (NSArray *)graphicsFromDrawDocumentDictionary:(NSDictionary *)doc {
    NSArray *graphicDicts = [doc objectForKey:SKTGraphicsListKey];
    unsigned i, c = [graphicDicts count];
    NSMutableArray *graphics = [NSMutableArray arrayWithCapacity:c];

    for (i=0; i<c; i++) {
        [graphics addObject:[SKTGraphic graphicWithPropertyListRepresentation:[graphicDicts objectAtIndex:i]]];
    }

    return graphics;
}

- (NSRect)boundsForGraphics:(NSArray *)graphics {
    NSRect rect = NSZeroRect;
    unsigned i, c = [graphics count];
    for (i=0; i<c; i++) {
        if (i==0) {
            rect = [[graphics objectAtIndex:i] bounds];
        } else {
            rect = NSUnionRect(rect, [[graphics objectAtIndex:i] bounds]);
        }
    }
    return rect;
}

- (NSRect)drawingBoundsForGraphics:(NSArray *)graphics {
    NSRect rect = NSZeroRect;
    unsigned i, c = [graphics count];
    for (i=0; i<c; i++) {
        if (i==0) {
            rect = [[graphics objectAtIndex:i] drawingBounds];
        } else {
            rect = NSUnionRect(rect, [[graphics objectAtIndex:i] drawingBounds]);
        }
    }
    return rect;
}

- (NSData *)TIFFRepresentationForGraphics:(NSArray *)graphics {
    NSRect bounds = [self drawingBoundsForGraphics:graphics];
    NSImage *image;
    NSData *tiffData;
    unsigned i = [graphics count];
    NSAffineTransform *transform;
    SKTGraphic *curGraphic;
    NSGraphicsContext *currentContext;

    if (NSIsEmptyRect(bounds)) {
        return nil;
    }
    image = [[NSImage allocWithZone:[self zone]] initWithSize:bounds.size];
    [image setFlipped:YES];
    [image lockFocus];
    // Get the context AFTER we lock focus
    currentContext = [NSGraphicsContext currentContext];
    transform = [NSAffineTransform transform];
    [transform translateXBy:-bounds.origin.x yBy:-bounds.origin.y];
    [transform concat];

    while (i-- > 0) {
        // The only reason a graphic knows what view it is drawing in is so that it can draw differently when being created or edited or selected.  A nil view means to draw in the standard way.
        curGraphic = [graphics objectAtIndex:i];
        [currentContext saveGraphicsState];
        [NSBezierPath clipRect:[curGraphic drawingBounds]];
        [curGraphic drawInView:nil isSelected:NO];
        [currentContext restoreGraphicsState];
    }
    [image unlockFocus];
    tiffData = [image TIFFRepresentation];
    [image release];
    return tiffData;
}

- (NSData *)PDFRepresentationForGraphics:(NSArray *)graphics {
    NSRect bounds = [self drawingBoundsForGraphics:graphics];
    SKTRenderingView *view = [[SKTRenderingView allocWithZone:[self zone]] initWithFrame:NSMakeRect(0.0, 0.0, NSMaxX(bounds), NSMaxY(bounds)) graphics:graphics];
    NSWindow *window = [[NSWindow allocWithZone:[self zone]] initWithContentRect:NSMakeRect(0.0, 0.0, NSMaxX(bounds), NSMaxY(bounds)) styleMask:NSBorderlessWindowMask backing:NSBackingStoreNonretained defer:NO];
    NSPrintInfo *printInfo = [self printInfo];
    NSMutableData *pdfData = [[NSMutableData allocWithZone:[self zone]] init];
    NSPrintOperation *printOp;

    [[window contentView] addSubview:view];
    [view release];
    printOp = [NSPrintOperation PDFOperationWithView:view insideRect:bounds toData:pdfData printInfo:printInfo];
    [printOp setShowPanels:NO];

    if ([printOp runOperation]) {
        [pdfData autorelease];
    } else {
        [pdfData release];
        pdfData = nil;
    }
    [window release];

    return pdfData;
}

- (NSData *)dataRepresentationOfType:(NSString *)type {
    if ([type isEqualToString:SKTDrawDocumentType]) {
        return [self drawDocumentDataForGraphics:[self graphics]];
    } else if ([type isEqualToString:NSTIFFPboardType]) {
        return [self TIFFRepresentationForGraphics:[self graphics]];
    } else if ([type isEqualToString:NSPDFPboardType]) {
        return [self PDFRepresentationForGraphics:[self graphics]];
    } else {
        return nil;
    }
}

- (BOOL)loadDataRepresentation:(NSData *)data ofType:(NSString *)type {
    if ([type isEqualToString:SKTDrawDocumentType]) {
        NSDictionary *doc = [self drawDocumentDictionaryFromData:data];
        [self setGraphics:[self graphicsFromDrawDocumentDictionary:doc]];

        data = [doc objectForKey:SKTPrintInfoKey];
        if (data) {
            NSPrintInfo *printInfo = [NSUnarchiver unarchiveObjectWithData:data];
            if (printInfo) {
                [self setPrintInfo:printInfo];
            }
        }

        [[self undoManager] removeAllActions];

        return YES;
    } else {
        return NO;
    }
}

- (void)updateChangeCount:(NSDocumentChangeType)change {
    // This clears the undo stack whenever we load or save.
    [super updateChangeCount:change];
    if (change == NSChangeCleared) {
        [[self undoManager] removeAllActions];
    }
}

- (NSWindow *)appropriateWindowForDocModalOperations {
    NSArray *wcs = [self windowControllers];
    unsigned i, c = [wcs count];
    NSWindow *docWindow = nil;
    
    for (i=0; i<c; i++) {
        docWindow = [[wcs objectAtIndex:i] window];
        if (docWindow) {
            break;
        }
    }
    return docWindow;
}

- (NSSize)documentSize {
    NSPrintInfo *printInfo = [self printInfo];
    NSSize paperSize = [printInfo paperSize];
    paperSize.width -= ([printInfo leftMargin] + [printInfo rightMargin]);
    paperSize.height -= ([printInfo topMargin] + [printInfo bottomMargin]);
    return paperSize;
}

- (void)printShowingPrintPanel:(BOOL)flag {
    NSSize paperSize = [self documentSize];
    SKTRenderingView *view = [[SKTRenderingView allocWithZone:[self zone]] initWithFrame:NSMakeRect(0.0, 0.0, paperSize.width, paperSize.height) graphics:[self graphics]];
    NSWindow *window = [[NSWindow allocWithZone:[self zone]] initWithContentRect:NSMakeRect(0.0, 0.0, paperSize.width, paperSize.height) styleMask:NSBorderlessWindowMask backing:NSBackingStoreNonretained defer:NO];
    NSPrintInfo *printInfo = [self printInfo];
    NSPrintOperation *printOp;
    NSWindow *docWindow = [self appropriateWindowForDocModalOperations];;

    [[window contentView] addSubview:view];
    [view release];
    printOp = [NSPrintOperation printOperationWithView:view printInfo:printInfo];
    [printOp setShowPanels:flag];
    [printOp setCanSpawnSeparateThread:YES];

    if (docWindow) {
        (void)[printOp runOperationModalForWindow:docWindow delegate:nil didRunSelector:NULL contextInfo:NULL];
    } else {
        (void)[printOp runOperation];
    }
    
    [window release];
}

- (void)setPrintInfo:(NSPrintInfo *)printInfo {
    [[[self undoManager] prepareWithInvocationTarget:self] setPrintInfo:[self printInfo]];
    [super setPrintInfo:printInfo];
    [[self undoManager] setActionName:NSLocalizedStringFromTable(@"Change Print Info", @"UndoStrings", @"Action name for changing print info.")];
    [[self windowControllers] makeObjectsPerformSelector:@selector(setUpGraphicView)];
}

- (NSArray *)graphics {
    return _graphics;
}

- (void)setGraphics:(NSArray *)graphics {
    unsigned i = [_graphics count];
    while (i-- > 0) {
        [self removeGraphicAtIndex:i];
    }
    i = [graphics count];
    while (i-- > 0) {
        [self insertGraphic:[graphics objectAtIndex:i] atIndex:0];
    }
}

- (void)invalidateGraphic:(SKTGraphic *)graphic {
    NSArray *windowControllers = [self windowControllers];

    [windowControllers makeObjectsPerformSelector:@selector(invalidateGraphic:) withObject:graphic];
}

- (void)insertGraphic:(SKTGraphic *)graphic atIndex:(unsigned)index {
    [[[self undoManager] prepareWithInvocationTarget:self] removeGraphicAtIndex:index];
    [_graphics insertObject:graphic atIndex:index];
    [graphic setDocument:self];
    [self invalidateGraphic:graphic];
}

- (void)removeGraphicAtIndex:(unsigned)index {
    id graphic = [[_graphics objectAtIndex:index] retain];
    [_graphics removeObjectAtIndex:index];
    [self invalidateGraphic:graphic];
    [[[self undoManager] prepareWithInvocationTarget:self] insertGraphic:graphic atIndex:index];
    [graphic release];
}

- (void)removeGraphic:(SKTGraphic *)graphic {
    unsigned index = [_graphics indexOfObjectIdenticalTo:graphic];
    if (index != NSNotFound) {
        [self removeGraphicAtIndex:index];
    }
}

- (void)moveGraphic:(SKTGraphic *)graphic toIndex:(unsigned)newIndex {
    unsigned curIndex = [_graphics indexOfObjectIdenticalTo:graphic];
    if (curIndex != newIndex) {
        [[[self undoManager] prepareWithInvocationTarget:self] moveGraphic:graphic toIndex:((curIndex > newIndex) ? curIndex+1 : curIndex)];
        if (curIndex < newIndex) {
            newIndex--;
        }
        [graphic retain];
        [_graphics removeObjectAtIndex:curIndex];
        [_graphics insertObject:graphic atIndex:newIndex];
        [graphic release];
        [self invalidateGraphic:graphic];
    }
}

@end

@implementation SKTDrawDocument (SKTScriptingExtras)

// These are methods that we probably wouldn't bother with if we weren't scriptable.

// graphics and setGraphics: are already implemented above.

- (void)addInGraphics:(SKTGraphic *)graphic {
    [self insertGraphic:graphic atIndex:[[self graphics] count]];
}

- (void)insertInGraphics:(SKTGraphic *)graphic atIndex:(unsigned)index {
    [self insertGraphic:graphic atIndex:index];
}

- (void)removeFromGraphicsAtIndex:(unsigned)index {
    [self removeGraphicAtIndex:index];
}

- (void)replaceInGraphics:(SKTGraphic *)graphic atIndex:(unsigned)index {
    [self removeGraphicAtIndex:index];
    [self insertGraphic:graphic atIndex:index];
}

- (NSArray *)graphicsWithClass:(Class)theClass {
    NSArray *graphics = [self graphics];
    NSMutableArray *result = [NSMutableArray array];
    unsigned i, c = [graphics count];
    id curGraphic;

    for (i=0; i<c; i++) {
        curGraphic = [graphics objectAtIndex:i];
        if ([curGraphic isKindOfClass:theClass]) {
            [result addObject:curGraphic];
        }
    }
    return result;
}

- (NSArray *)rectangles {
    return [self graphicsWithClass:[SKTRectangle class]];
}

- (NSArray *)circles {
    return [self graphicsWithClass:[SKTCircle class]];
}

- (NSArray *)lines {
    return [self graphicsWithClass:[SKTLine class]];
}

- (NSArray *)textAreas {
    return [self graphicsWithClass:[SKTTextArea class]];
}

- (NSArray *)images {
    return [self graphicsWithClass:[SKTImage class]];
}

- (void)setRectangles:(NSArray *)rects {
    // We won't allow wholesale setting of these subset keys.
    [NSException raise:NSOperationNotSupportedForKeyException format:@"Setting 'rectangles' key is not supported."];
}

- (void)addInRectangles:(SKTGraphic *)graphic {
    [self addInGraphics:graphic];
}

- (void)insertInRectangles:(SKTGraphic *)graphic atIndex:(unsigned)index {
    // MF:!!! This is not going to be ideal.  If we are being asked to, say, "make a new rectangle at after rectangle 2", we will be after rectangle 2, but we may be after some other stuff as well since we will be asked to insertInRectangles:atIndex:3...
    NSArray *rects = [self rectangles];
    if (index == [rects count]) {
        [self addInGraphics:graphic];
    } else {
        NSArray *graphics = [self graphics];
        int newIndex = [graphics indexOfObjectIdenticalTo:[rects objectAtIndex:index]];
        if (newIndex != NSNotFound) {
            [self insertGraphic:graphic atIndex:newIndex];
        } else {
            // Shouldn't happen.
            [NSException raise:NSRangeException format:@"Could not find the given rectangle in the graphics."];
        }
    }
}

- (void)removeFromRectanglesAtIndex:(unsigned)index {
    NSArray *rects = [self rectangles];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[rects objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given rectangle in the graphics."];
    }
}

- (void)replaceInRectangles:(SKTGraphic *)graphic atIndex:(unsigned)index {
    NSArray *rects = [self rectangles];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[rects objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
        [self insertGraphic:graphic atIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given rectangle in the graphics."];
    }
}

- (void)setCircles:(NSArray *)circles {
    // We won't allow wholesale setting of these subset keys.
    [NSException raise:NSOperationNotSupportedForKeyException format:@"Setting 'circles' key is not supported."];
}

- (void)addInCircles:(SKTGraphic *)graphic {
    [self addInGraphics:graphic];
}

- (void)insertInCircles:(SKTGraphic *)graphic atIndex:(unsigned)index {
    // MF:!!! This is not going to be ideal.  If we are being asked to, say, "make a new rectangle at after rectangle 2", we will be after rectangle 2, but we may be after some other stuff as well since we will be asked to insertInCircles:atIndex:3...
    NSArray *circles = [self circles];
    if (index == [circles count]) {
        [self addInGraphics:graphic];
    } else {
        NSArray *graphics = [self graphics];
        int newIndex = [graphics indexOfObjectIdenticalTo:[circles objectAtIndex:index]];
        if (newIndex != NSNotFound) {
            [self insertGraphic:graphic atIndex:newIndex];
        } else {
            // Shouldn't happen.
            [NSException raise:NSRangeException format:@"Could not find the given circle in the graphics."];
        }
    }
}

- (void)removeFromCirclesAtIndex:(unsigned)index {
    NSArray *circles = [self circles];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[circles objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given circle in the graphics."];
    }
}

- (void)replaceInCircles:(SKTGraphic *)graphic atIndex:(unsigned)index {
    NSArray *circles = [self circles];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[circles objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
        [self insertGraphic:graphic atIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given circle in the graphics."];
    }
}

- (void)setLines:(NSArray *)lines {
    // We won't allow wholesale setting of these subset keys.
    [NSException raise:NSOperationNotSupportedForKeyException format:@"Setting 'lines' key is not supported."];
}

- (void)addInLines:(SKTGraphic *)graphic {
    [self addInGraphics:graphic];
}

- (void)insertInLines:(SKTGraphic *)graphic atIndex:(unsigned)index {
    // MF:!!! This is not going to be ideal.  If we are being asked to, say, "make a new rectangle at after rectangle 2", we will be after rectangle 2, but we may be after some other stuff as well since we will be asked to insertInLines:atIndex:3...
    NSArray *lines = [self lines];
    if (index == [lines count]) {
        [self addInGraphics:graphic];
    } else {
        NSArray *graphics = [self graphics];
        int newIndex = [graphics indexOfObjectIdenticalTo:[lines objectAtIndex:index]];
        if (newIndex != NSNotFound) {
            [self insertGraphic:graphic atIndex:newIndex];
        } else {
            // Shouldn't happen.
            [NSException raise:NSRangeException format:@"Could not find the given line in the graphics."];
        }
    }
}

- (void)removeFromLinesAtIndex:(unsigned)index {
    NSArray *lines = [self lines];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[lines objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given line in the graphics."];
    }
}

- (void)replaceInLines:(SKTGraphic *)graphic atIndex:(unsigned)index {
    NSArray *lines = [self lines];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[lines objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
        [self insertGraphic:graphic atIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given line in the graphics."];
    }
}

- (void)setTextAreas:(NSArray *)textAreas {
    // We won't allow wholesale setting of these subset keys.
    [NSException raise:NSOperationNotSupportedForKeyException format:@"Setting 'textAreas' key is not supported."];
}

- (void)addInTextAreas:(SKTGraphic *)graphic {
    [self addInGraphics:graphic];
}

- (void)insertInTextAreas:(SKTGraphic *)graphic atIndex:(unsigned)index {
    // MF:!!! This is not going to be ideal.  If we are being asked to, say, "make a new rectangle at after rectangle 2", we will be after rectangle 2, but we may be after some other stuff as well since we will be asked to insertInTextAreas:atIndex:3...
    NSArray *textAreas = [self textAreas];
    if (index == [textAreas count]) {
        [self addInGraphics:graphic];
    } else {
        NSArray *graphics = [self graphics];
        int newIndex = [graphics indexOfObjectIdenticalTo:[textAreas objectAtIndex:index]];
        if (newIndex != NSNotFound) {
            [self insertGraphic:graphic atIndex:newIndex];
        } else {
            // Shouldn't happen.
            [NSException raise:NSRangeException format:@"Could not find the given text area in the graphics."];
        }
    }
}

- (void)removeFromTextAreasAtIndex:(unsigned)index {
    NSArray *textAreas = [self textAreas];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[textAreas objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given text area in the graphics."];
    }
}

- (void)replaceInTextAreas:(SKTGraphic *)graphic atIndex:(unsigned)index {
    NSArray *textAreas = [self textAreas];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[textAreas objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
        [self insertGraphic:graphic atIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given text area in the graphics."];
    }
}

- (void)setImages:(NSArray *)images {
    // We won't allow wholesale setting of these subset keys.
    [NSException raise:NSOperationNotSupportedForKeyException format:@"Setting 'images' key is not supported."];
}

- (void)addInImages:(SKTGraphic *)graphic {
    [self addInGraphics:graphic];
}

- (void)insertInImages:(SKTGraphic *)graphic atIndex:(unsigned)index {
    // MF:!!! This is not going to be ideal.  If we are being asked to, say, "make a new rectangle at after rectangle 2", we will be after rectangle 2, but we may be after some other stuff as well since we will be asked to insertInImages:atIndex:3...
    NSArray *images = [self images];
    if (index == [images count]) {
        [self addInGraphics:graphic];
    } else {
        NSArray *graphics = [self graphics];
        int newIndex = [graphics indexOfObjectIdenticalTo:[images objectAtIndex:index]];
        if (newIndex != NSNotFound) {
            [self insertGraphic:graphic atIndex:newIndex];
        } else {
            // Shouldn't happen.
            [NSException raise:NSRangeException format:@"Could not find the given image in the graphics."];
        }
    }
}

- (void)removeFromImagesAtIndex:(unsigned)index {
    NSArray *images = [self images];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[images objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given image in the graphics."];
    }
}

- (void)replaceInImages:(SKTGraphic *)graphic atIndex:(unsigned)index {
    NSArray *images = [self images];
    NSArray *graphics = [self graphics];
    int newIndex = [graphics indexOfObjectIdenticalTo:[images objectAtIndex:index]];
    if (newIndex != NSNotFound) {
        [self removeGraphicAtIndex:newIndex];
        [self insertGraphic:graphic atIndex:newIndex];
    } else {
        // Shouldn't happen.
        [NSException raise:NSRangeException format:@"Could not find the given image in the graphics."];
    }
}

// The following "indicesOf..." methods are in support of scripting.  They allow more flexible range and relative specifiers to be used with the different graphic keys of a SKTDrawDocument.
// The scripting engine does not know about the fact that the "rectangles" key is really just a subset of the "graphics" key, so script code like "rectangles from circle 1 to line 4" don't make sense to it.  But Sketch does know and can answer such questions itself, with a little work.
- (NSArray *)indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *)rangeSpec {
    NSString *key = [rangeSpec key];

    if ([key isEqual:@"graphics"] || [key isEqual:@"rectangles"] || [key isEqual:@"circles"] || [key isEqual:@"lines"] || [key isEqual:@"textAreas"] || [key isEqual:@"images"]) {
        // This is one of the keys we might want to deal with.
        NSScriptObjectSpecifier *startSpec = [rangeSpec startSpecifier];
        NSScriptObjectSpecifier *endSpec = [rangeSpec endSpecifier];
        NSString *startKey = [startSpec key];
        NSString *endKey = [endSpec key];
        NSArray *graphics = [self graphics];

        if ((startSpec == nil) && (endSpec == nil)) {
            // We need to have at least one of these...
            return nil;
        }
        if ([graphics count] == 0) {
            // If there are no graphics, there can be no match.  Just return now.
            return [NSArray array];
        }

        if ((!startSpec || [startKey isEqual:@"graphics"] || [startKey isEqual:@"rectangles"] || [startKey isEqual:@"circles"] || [startKey isEqual:@"lines"] || [startKey isEqual:@"textAreas"] || [startKey isEqual:@"images"]) && (!endSpec || [endKey isEqual:@"graphics"] || [endKey isEqual:@"rectangles"] || [endKey isEqual:@"circles"] || [endKey isEqual:@"lines"] || [endKey isEqual:@"textAreas"] || [endKey isEqual:@"images"])) {
            int startIndex;
            int endIndex;

            // The start and end keys are also ones we want to handle.

            // The strategy here is going to be to find the index of the start and stop object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for in that range of the graphics key (weeding out objects we don't want, if necessary).

            // First find the index of the first start object in the graphics array
            if (startSpec) {
                id startObject = [startSpec objectsByEvaluatingSpecifier];
                if ([startObject isKindOfClass:[NSArray class]]) {
                    if ([startObject count] == 0) {
                        startObject = nil;
                    } else {
                        startObject = [startObject objectAtIndex:0];
                    }
                }
                if (!startObject) {
                    // Oops.  We could not find the start object.
                    return nil;
                }
                startIndex = [graphics indexOfObjectIdenticalTo:startObject];
                if (startIndex == NSNotFound) {
                    // Oops.  We couldn't find the start object in the graphics array.  This should not happen.
                    return nil;
                }
            } else {
                startIndex = 0;
            }

            // Now find the index of the last end object in the graphics array
            if (endSpec) {
                id endObject = [endSpec objectsByEvaluatingSpecifier];
                if ([endObject isKindOfClass:[NSArray class]]) {
                    unsigned endObjectsCount = [endObject count];
                    if (endObjectsCount == 0) {
                        endObject = nil;
                    } else {
                        endObject = [endObject objectAtIndex:(endObjectsCount-1)];
                    }
                }
                if (!endObject) {
                    // Oops.  We could not find the end object.
                    return nil;
                }
                endIndex = [graphics indexOfObjectIdenticalTo:endObject];
                if (endIndex == NSNotFound) {
                    // Oops.  We couldn't find the end object in the graphics array.  This should not happen.
                    return nil;
                }
            } else {
                endIndex = [graphics count] - 1;
            }

            if (endIndex < startIndex) {
                // Accept backwards ranges gracefully
                int temp = endIndex;
                endIndex = startIndex;
                startIndex = temp;
            }

            {
                // Now startIndex and endIndex specify the end points of the range we want within the graphics array.
                // We will traverse the range and pick the objects we want.
                // We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
                NSMutableArray *result = [NSMutableArray array];
                BOOL keyIsGraphics = [key isEqual:@"graphics"];
                NSArray *rangeKeyObjects = (keyIsGraphics ? nil : [self valueForKey:key]);
                id curObj;
                unsigned curKeyIndex, i;

                for (i=startIndex; i<=endIndex; i++) {
                    if (keyIsGraphics) {
                        [result addObject:[NSNumber numberWithInt:i]];
                    } else {
                        curObj = [graphics objectAtIndex:i];
                        curKeyIndex = [rangeKeyObjects indexOfObjectIdenticalTo:curObj];
                        if (curKeyIndex != NSNotFound) {
                            [result addObject:[NSNumber numberWithInt:curKeyIndex]];
                        }
                    }
                }
                return result;
            }
        }
    }
    return nil;
}

- (NSArray *)indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *)relSpec {
    NSString *key = [relSpec key];

    if ([key isEqual:@"graphics"] || [key isEqual:@"rectangles"] || [key isEqual:@"circles"] || [key isEqual:@"lines"] || [key isEqual:@"textAreas"] || [key isEqual:@"images"]) {
        // This is one of the keys we might want to deal with.
        NSScriptObjectSpecifier *baseSpec = [relSpec baseSpecifier];
        NSString *baseKey = [baseSpec key];
        NSArray *graphics = [self graphics];
        NSRelativePosition relPos = [relSpec relativePosition];

        if (baseSpec == nil) {
            // We need to have one of these...
            return nil;
        }
        if ([graphics count] == 0) {
            // If there are no graphics, there can be no match.  Just return now.
            return [NSArray array];
        }

        if ([baseKey isEqual:@"graphics"] || [baseKey isEqual:@"rectangles"] || [baseKey isEqual:@"circles"] || [baseKey isEqual:@"lines"] || [baseKey isEqual:@"textAreas"] || [baseKey isEqual:@"images"]) {
            int baseIndex;

            // The base key is also one we want to handle.

            // The strategy here is going to be to find the index of the base object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for before or after it.

            // First find the index of the first or last base object in the graphics array
            // Base specifiers are to be evaluated within the same container as the relative specifier they are the base of.  That's this document.
            id baseObject = [baseSpec objectsByEvaluatingWithContainers:self];
            if ([baseObject isKindOfClass:[NSArray class]]) {
                int baseCount = [baseObject count];
                if (baseCount == 0) {
                    baseObject = nil;
                } else {
                    if (relPos == NSRelativeBefore) {
                        baseObject = [baseObject objectAtIndex:0];
                    } else {
                        baseObject = [baseObject objectAtIndex:(baseCount-1)];
                    }
                }
            }
            if (!baseObject) {
                // Oops.  We could not find the base object.
                return nil;
            }

            baseIndex = [graphics indexOfObjectIdenticalTo:baseObject];
            if (baseIndex == NSNotFound) {
                // Oops.  We couldn't find the base object in the graphics array.  This should not happen.
                return nil;
            }

            {
                // Now baseIndex specifies the base object for the relative spec in the graphics array.
                // We will start either right before or right after and look for an object that matches the type we want.
                // We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
                NSMutableArray *result = [NSMutableArray array];
                BOOL keyIsGraphics = [key isEqual:@"graphics"];
                NSArray *relKeyObjects = (keyIsGraphics ? nil : [self valueForKey:key]);
                id curObj;
                unsigned curKeyIndex, graphicCount = [graphics count];

                if (relPos == NSRelativeBefore) {
                    baseIndex--;
                } else {
                    baseIndex++;
                }
                while ((baseIndex >= 0) && (baseIndex < graphicCount)) {
                    if (keyIsGraphics) {
                        [result addObject:[NSNumber numberWithInt:baseIndex]];
                        break;
                    } else {
                        curObj = [graphics objectAtIndex:baseIndex];
                        curKeyIndex = [relKeyObjects indexOfObjectIdenticalTo:curObj];
                        if (curKeyIndex != NSNotFound) {
                            [result addObject:[NSNumber numberWithInt:curKeyIndex]];
                            break;
                        }
                    }
                    if (relPos == NSRelativeBefore) {
                        baseIndex--;
                    } else {
                        baseIndex++;
                    }
                }

                return result;
            }
        }
    }
    return nil;
}
    
- (NSArray *)indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *)specifier {
    // We want to handle some range and relative specifiers ourselves in order to support such things as "graphics from circle 3 to circle 5" or "circles from graphic 1 to graphic 10" or "circle before rectangle 3".
    // Returning nil from this method will cause the specifier to try to evaluate itself using its default evaluation strategy.
	
    if ([specifier isKindOfClass:[NSRangeSpecifier class]]) {
        return [self indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *)specifier];
    } else if ([specifier isKindOfClass:[NSRelativeSpecifier class]]) {
        return [self indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *)specifier];
    }


    // If we didn't handle it, return nil so that the default object specifier evaluation will do it.
    return nil;
}


@end


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
