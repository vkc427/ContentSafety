#import "SCABridge.h"

@implementation SCABridge
+ (NSException * _Nullable)tryCatch:(void (^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
@end
