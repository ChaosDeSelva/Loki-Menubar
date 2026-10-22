#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "LOKMenuBarBridge.h"

// Runtime stand-ins: this executable never loads or contacts the real framework.
@interface MBAssessmentModeConfiguration : NSObject
- (id)initWithAllowedSystemItems:(NSArray *)items allowedBundleIdentifiers:(NSArray *)bundles;
@end
@implementation MBAssessmentModeConfiguration
- (id)initWithAllowedSystemItems:(NSArray *)items allowedBundleIdentifiers:(NSArray *)bundles { return [super init]; }
@end
@interface MBAssessmentModeAssertion : NSObject
@property BOOL invalidated;
@property(copy) void (^reply)(NSError *);
- (void)activateWithConfiguration:(id)config completionHandler:(void (^)(NSError *))completion;
- (void)invalidate;
@end
static NSMutableArray<MBAssessmentModeAssertion *> *requests;
@implementation MBAssessmentModeAssertion
- (void)activateWithConfiguration:(id)config completionHandler:(void (^)(NSError *))completion {
    self.reply = completion; [requests addObject:self];
}
- (void)invalidate { self.invalidated = YES; }
@end
static BOOL available(id self, SEL command) { return YES; }
static int checks;
static void check(BOOL value, NSString *label) {
    if (!value) { fprintf(stderr,"FAIL: %s\n",label.UTF8String); exit(1); }
    printf("PASS: %s\n",label.UTF8String); checks++;
}
static void drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]]; }
int main() { @autoreleasepool {
    requests = [NSMutableArray new];
    method_setImplementation(class_getClassMethod(LOKMenuBarBridge.class, @selector(available)), (IMP)available);
    LOKMenuBarBridge *bridge = [LOKMenuBarBridge new];
    __block NSUInteger completions = 0;
    void (^success)(NSError *) = ^(NSError *error) { check(error == nil, @"Accepted result has no error"); completions++; };
    [bridge applyAllowedBundles:@[@"self"] systemItems:@[@0] completion:success];
    MBAssessmentModeAssertion *first = requests.lastObject;
    [bridge invalidate];
    first.reply(nil); drain();
    check(first.invalidated && completions == 0, @"Cancel suppresses late success and releases assertion");

    [bridge applyAllowedBundles:@[@"self"] systemItems:@[@0] completion:success];
    MBAssessmentModeAssertion *old = requests.lastObject;
    [bridge applyAllowedBundles:@[@"self", @"other"] systemItems:@[@0] completion:success];
    MBAssessmentModeAssertion *current = requests.lastObject;
    old.reply(nil); drain();
    check(old.invalidated && !current.invalidated && completions == 0, @"Stale success cannot cancel the replacement");
    current.reply(nil); drain();
    check(completions == 1 && !current.invalidated, @"Current success remains active until reveal");
    [bridge invalidate];
    check(current.invalidated, @"Reveal releases current assertion");

    __block BOOL failed = NO;
    [bridge applyAllowedBundles:@[@"self"] systemItems:@[@0] completion:^(NSError *error) { failed = error != nil; }];
    MBAssessmentModeAssertion *rejected = requests.lastObject;
    rejected.reply([NSError errorWithDomain:@"Test" code:1 userInfo:nil]); drain();
    check(failed && rejected.invalidated, @"Server error releases assertion and reaches caller");

    NSUInteger before = requests.count;
    [bridge applyAllowedBundles:@[@"self"] systemItems:@[] completion:^(NSError *error) { failed = error != nil; }];
    check(failed && requests.count == before, @"Empty system allowlist never reaches the server");

    @autoreleasepool {
        LOKMenuBarBridge *temporary = [LOKMenuBarBridge new];
        [temporary applyAllowedBundles:@[@"self"] systemItems:@[@0] completion:success];
    }
    MBAssessmentModeAssertion *orphan = requests.lastObject;
    check(orphan.invalidated, @"Owner destruction invalidates pending assertion");
    orphan.reply(nil); drain();
    check(completions == 1, @"Destroyed owner cannot publish late success");
    for (MBAssessmentModeAssertion *request in requests) request.reply = nil;
    printf("%d bridge lifecycle checks passed\n",checks);
}}
