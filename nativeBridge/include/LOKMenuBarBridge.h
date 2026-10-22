#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface LOKMenuBarBridge : NSObject
@property(class, nonatomic, readonly) BOOL available;
- (void)applyAllowedBundles:(NSArray<NSString *> *)bundles
               systemItems:(NSArray<NSNumber *> *)items
                completion:(void (^)(NSError * _Nullable))completion;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
