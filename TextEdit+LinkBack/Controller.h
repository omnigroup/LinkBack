#import <Cocoa/Cocoa.h>

@interface Controller : NSObject {
    id infoPanel;
    NSMutableArray *openFailures;	// Files that couldn't be opened
}

/* NSApplication delegate methods */
- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename;
- (BOOL)application:(NSApplication *)app openTempFile:(NSString *)filename;
- (BOOL)applicationOpenUntitledFile:(NSApplication *)app;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app;

/* Action methods */
- (void)createNew:(id)sender;
- (void)open:(id)sender;
- (void)saveAll:(id)sender;

@end
