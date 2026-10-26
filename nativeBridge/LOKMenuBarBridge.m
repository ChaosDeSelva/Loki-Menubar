#import "LOKMenuBarBridge.h"
#import <objc/runtime.h>
#import <dlfcn.h>

// Declarations describe selectors observed in Apple's installed runtime.
// No private framework is linked, bundled, or required on older macOS.
@protocol LOKConfiguration
- (id)initWithAllowedSystemItems:(NSArray *)items allowedBundleIdentifiers:(NSArray *)bundles;
@end
@protocol LOKAssertion
- (void)activateWithConfiguration:(id)configuration completionHandler:(void (^)(NSError *))completion;
- (void)invalidate;
@end

static BOOL LOKLoad(void) {
    static BOOL loaded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 27) return;
        if (!dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW | RTLD_LOCAL)) return;
        Class config = NSClassFromString(@"MBAssessmentModeConfiguration");
        Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
        loaded = [config instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)]
            && [assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)]
            && [assertion instancesRespondToSelector:@selector(invalidate)];
    });
    return loaded;
}
// Make before break: a confirmed assertion stays active until its replacement is confirmed,
// so refreshing the allowlist (for example when an app launches) never flashes hidden icons.
@implementation LOKMenuBarBridge {
    id<LOKAssertion> _active;
    id<LOKAssertion> _pending;
    NSUInteger _generation;
}
+ (BOOL)available { return LOKLoad(); }
- (void)invalidate {
    NSAssert(NSThread.isMainThread, @"Menu-bar lifecycle must run on the main thread");
    ++_generation;
    [_pending invalidate]; _pending = nil;
    [_active invalidate]; _active = nil;
}
- (void)applyAllowedBundles:(NSArray<NSString *> *)bundles systemItems:(NSArray<NSNumber *> *)items completion:(void (^)(NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Menu-bar lifecycle must run on the main thread");
    NSUInteger generation = ++_generation;
    [_pending invalidate]; _pending = nil;
    NSError *(^failure)(NSString *) = ^NSError *(NSString *message) {
        return [NSError errorWithDomain:@"Loki.MenuBar" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    };
    if (!self.class.available || items.count == 0) { completion(failure(@"This macOS version does not expose the expected menu-bar controls.")); return; }
    @try {
        id<LOKConfiguration> config = [(id<LOKConfiguration>)[NSClassFromString(@"MBAssessmentModeConfiguration") alloc]
            initWithAllowedSystemItems:items allowedBundleIdentifiers:bundles];
        id<LOKAssertion> candidate = [NSClassFromString(@"MBAssessmentModeAssertion") new];
        _pending = candidate;
        __weak LOKMenuBarBridge *weakSelf = self;
        [candidate activateWithConfiguration:config completionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                LOKMenuBarBridge *owner = weakSelf;
                if (!owner || owner->_generation != generation || owner->_pending != candidate) { [candidate invalidate]; return; }
                owner->_pending = nil;
                if (error) { [candidate invalidate]; completion(error); return; }
                [owner->_active invalidate];
                owner->_active = candidate;
                completion(nil);
            });
        }];
    } @catch (NSException *exception) {
        [self invalidate];
        completion(failure(@"macOS rejected the menu-bar configuration. Icons have been revealed."));
    }
}
- (void)dealloc { [_pending invalidate]; [_active invalidate]; }
@end
