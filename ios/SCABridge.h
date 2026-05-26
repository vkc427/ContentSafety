#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCABridge : NSObject
/// Executes block, catching any NSException. Returns the exception or nil.
+ (NSException * _Nullable)tryCatch:(void (^)(void))block;
@end

NS_ASSUME_NONNULL_END
