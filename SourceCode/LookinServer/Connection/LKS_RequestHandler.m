//
//  LKS_RequestHandler.m
//  LookinServer
//
//  Copyright © 2019 hughkli. All rights reserved.
//

#import "LKS_RequestHandler.h"
#import "LKS_ConnectionManager.h"
#import "LookinConnectionResponseAttachment.h"
#import "LookinDefines.h"
#import "LookinAttributeModification.h"
#import "LookinDisplayItemDetail.h"
#import "LookinHierarchyInfo.h"
#import <objc/runtime.h>
#import "LookinObject.h"
#import "LookinObjectIvar.h"
#import "LKS_LocalInspectManager.h"
#import "LookinAppInfo.h"
#import "LKS_MethodTraceManager.h"
#import "LKS_AttrGroupsMaker.h"
#import "LKS_AttrModificationHandler.h"
#import "LKS_AttrModificationPatchHandler.h"
#import "LKS_HierarchyDetailsHandler.h"
#import "LookinStaticAsyncUpdateTask.h"

@interface LKS_RequestHandler ()

@end

@implementation LKS_RequestHandler {
    NSSet *_validRequestTypes;
}

- (instancetype)init {
    if (self = [super init]) {
        _validRequestTypes = [NSSet setWithObjects:@(LookinRequestTypePing),
                              @(LookinRequestTypeApp),
                              @(LookinRequestTypeHierarchy),
                              @(LookinRequestTypeModification),
                              @(LookinRequestTypeAttrModificationPatch),
                              @(LookinRequestTypeHierarchyDetails),
                              @(LookinRequestTypeFetchObject),
                              @(LookinRequestTypeAllAttrGroups),
                              @(LookinRequestTypeAllSelectorNames),
                              @(LookinRequestTypeAddMethodTrace),
                              @(LookinRequestTypeDeleteMethodTrace),
                              @(LookinRequestTypeClassesAndMethodTraceLit),
                              @(LookinRequestTypeInvokeMethod),
                              
                              @(LookinPush_BringForwardScreenshotTask),
                              nil];
    }
    return self;
}

- (BOOL)canHandleRequestType:(uint32_t)requestType {
    if ([_validRequestTypes containsObject:@(requestType)]) {
        return YES;
    }
    NSAssert(NO, @"");
    return NO;
}

- (void)handleRequestType:(uint32_t)requestType tag:(uint32_t)tag object:(id)object {
    if (requestType == LookinRequestTypePing) {
        if ([LKS_ConnectionManager sharedInstance].applicationIsActive) {
            LookinConnectionResponseAttachment *responseAttachment = [LookinConnectionResponseAttachment new];
            [[LKS_ConnectionManager sharedInstance] respond:responseAttachment requestType:requestType tag:tag];            
        }
        
    } else if (requestType == LookinRequestTypeApp) {
        // 请求可用设备信息
        NSDictionary *params = (NSDictionary *)object;
        
        LookinAppsFetchScreenshotType screenshotType = [[params objectForKey:@"screenshotType"] integerValue];
        NSArray<LookinAppInfo *> *appInfos = [params objectForKey:@"appInfos"];
        LookinAppInfo *appInfo = [LookinAppInfo currentInfoWithScreenshotType:screenshotType appInfos:appInfos];
        
        LookinConnectionResponseAttachment *responseAttachment = [LookinConnectionResponseAttachment new];
        responseAttachment.data = appInfo;
        [[LKS_ConnectionManager sharedInstance] respond:responseAttachment requestType:requestType tag:tag];
        
    } else if (requestType == LookinRequestTypeHierarchy) {
        LookinConnectionResponseAttachment *responseAttachment = [LookinConnectionResponseAttachment new];
        responseAttachment.data = [LookinHierarchyInfo staticInfo];
        [[LKS_ConnectionManager sharedInstance] respond:responseAttachment requestType:requestType tag:tag];
        
    } else if (requestType == LookinRequestTypeModification) {
        // 请求修改某个属性
        [LKS_AttrModificationHandler handleModification:object completion:^(LookinDisplayItemDetail *data, NSError *error) {
            LookinConnectionResponseAttachment *attachment = [LookinConnectionResponseAttachment new];
            if (error) {
                attachment.error = error;
            } else {
                attachment.data = data;
            }
            [[LKS_ConnectionManager sharedInstance] respond:attachment requestType:requestType tag:tag];
        }];
        
    } else if (requestType == LookinRequestTypeAttrModificationPatch) {
        NSArray<LookinStaticAsyncUpdateTask *> *tasks = object;
        NSUInteger dataTotalCount = tasks.count;
        [LKS_AttrModificationHandler handlePatchWithTasks:tasks block:^(LookinDisplayItemDetail *data) {
            LookinConnectionResponseAttachment *attrAttachment = [LookinConnectionResponseAttachment new];
            attrAttachment.data = data;
            attrAttachment.dataTotalCount = dataTotalCount;
            attrAttachment.currentDataCount = 1;
            [[LKS_ConnectionManager sharedInstance] respond:attrAttachment requestType:LookinRequestTypeAttrModificationPatch tag:tag];
        }];
        
    } else if (requestType == LookinRequestTypeHierarchyDetails) {
        NSArray<LookinStaticAsyncUpdateTasksPackage *> *packages = object;
        NSUInteger responsesDataTotalCount = [packages lookin_reduceInteger:^NSInteger(NSInteger accumulator, NSUInteger idx, LookinStaticAsyncUpdateTasksPackage *package) {
            accumulator += package.tasks.count;
            return accumulator;
        } initialAccumlator:0];
        
        [[LKS_HierarchyDetailsHandler sharedInstance] startWithPackages:packages block:^(NSArray<LookinDisplayItemDetail *> *details, NSError *error) {
            LookinConnectionResponseAttachment *attachment = [LookinConnectionResponseAttachment new];
            attachment.error = error;
            attachment.data = details;
            attachment.dataTotalCount = responsesDataTotalCount;
            attachment.currentDataCount = details.count;
            [[LKS_ConnectionManager sharedInstance] respond:attachment requestType:LookinRequestTypeHierarchyDetails tag:tag];
        }];
        
    } else if (requestType == LookinRequestTypeFetchObject) {
        unsigned long oid = ((NSNumber *)object).unsignedLongValue;
        NSObject *object = [NSObject lks_objectWithOid:oid];
        LookinObject *lookinObj = [LookinObject instanceWithObject:object];
        
        LookinConnectionResponseAttachment *attach = [LookinConnectionResponseAttachment new];
        attach.data = lookinObj;
        [[LKS_ConnectionManager sharedInstance] respond:attach requestType:requestType tag:tag];
        
    } else if (requestType == LookinRequestTypeAllAttrGroups) {
        unsigned long oid = ((NSNumber *)object).unsignedLongValue;
        CALayer *layer = (CALayer *)[NSObject lks_objectWithOid:oid];
        if (![layer isKindOfClass:[CALayer class]]) {
            [self _submitResponseWithError:LookinErr_ObjNotFound requestType:LookinRequestTypeAllAttrGroups tag:tag];
            return;
        }
        
        NSArray<LookinAttributesGroup *> *list = [LKS_AttrGroupsMaker attrGroupsForLayer:layer];
        [self _submitResponseWithData:list requestType:LookinRequestTypeAllAttrGroups tag:tag];
        
    } else if (requestType == LookinRequestTypeAllSelectorNames) {
        Class targetClass = NSClassFromString(object);
        if (!targetClass) {
            NSString *errorMsg = [NSString stringWithFormat:LKS_Localized(@"Didn't find the class named \"%@\". Please input another class and try again."), object];
            [self _submitResponseWithError:LookinErrorMake(errorMsg, @"") requestType:requestType tag:tag];
            return;
        }
        
        NSArray<NSString *> *selNames = [self _methodNameListForClass:targetClass];
        [self _submitResponseWithData:selNames requestType:requestType tag:tag];
        
    } else if (requestType == LookinRequestTypeAddMethodTrace) {
        if (![object isKindOfClass:[NSDictionary class]]) {
            [self _submitResponseWithError:LookinErr_Inner requestType:requestType tag:tag];
            return;
        }
        NSDictionary *dict = object;
        NSString *className = dict[@"className"];
        NSString *selName = dict[@"selName"];
        
        Class targetClass = NSClassFromString(className);
        if (!targetClass) {
            NSString *errorMsg = [NSString stringWithFormat:LKS_Localized(@"Didn't find the class named \"%@\". Please input another class and try again."), object];
            [self _submitResponseWithError:LookinErrorMake(errorMsg, @"") requestType:requestType tag:tag];
            return;
        }
        
        SEL targetSelector = NSSelectorFromString(selName);
        if (class_getInstanceMethod(targetClass, targetSelector) == NULL) {
            NSString *errorMsg = [NSString stringWithFormat:LKS_Localized(@"%@ doesn't have a method called %@. Please input another method name and try again."), className, selName];
            [self _submitResponseWithError:LookinErrorMake(errorMsg, @"") requestType:requestType tag:tag];
            return;
        }
        
        [[LKS_MethodTraceManager sharedInstance] addWithClassName:className selName:selName];
        [self _submitResponseWithData:[LKS_MethodTraceManager sharedInstance].currentActiveTraceList requestType:requestType tag:tag];
        
    } else if (requestType == LookinRequestTypeDeleteMethodTrace) {
        if (![object isKindOfClass:[NSDictionary class]]) {
            [self _submitResponseWithError:LookinErr_Inner requestType:requestType tag:tag];
            return;
        }
        NSDictionary *dict = object;
        NSString *className = dict[@"className"];
        NSString *selName = dict[@"selName"];
        
        [[LKS_MethodTraceManager sharedInstance] removeWithClassName:className selName:selName];
        [self _submitResponseWithData:[LKS_MethodTraceManager sharedInstance].currentActiveTraceList requestType:requestType tag:tag];
        
    } else if (requestType == LookinRequestTypeClassesAndMethodTraceLit) {
        LKS_MethodTraceManager *mng = [LKS_MethodTraceManager sharedInstance];
        NSDictionary *dict = @{@"classes":mng.allClassesListInApp, @"activeList":mng.currentActiveTraceList};
        [self _submitResponseWithData:dict requestType:requestType tag:tag];
        
    } else if (requestType == LookinRequestTypeInvokeMethod) {
        NSDictionary *param = object;
        unsigned long oid = [param[@"oid"] unsignedLongValue];
        NSString *text = param[@"text"];
        if (!text.length) {
            [self _submitResponseWithError:LookinErr_Inner requestType:requestType tag:tag];
            return;
        }
        NSObject *targerObj = [NSObject lks_objectWithOid:oid];
        if (!targerObj) {
            [self _submitResponseWithError:LookinErr_ObjNotFound requestType:requestType tag:tag];
            return;
        }
        
        SEL targetSelector = NSSelectorFromString(text);
        if (targetSelector && [targerObj respondsToSelector:targetSelector]) {
            NSString *resultDescription;
            NSObject *resultObject;
            NSError *error;
            [self _handleInvokeWithObject:targerObj selector:targetSelector resultDescription:&resultDescription resultObject:&resultObject error:&error];
            if (error) {
                [self _submitResponseWithError:error requestType:requestType tag:tag];
                return;
            }
            NSMutableDictionary *responseData = [NSMutableDictionary dictionaryWithCapacity:2];
            if (resultDescription) {
                responseData[@"description"] = resultDescription;
            }
            if (resultObject) {
                responseData[@"object"] = resultObject;
            }
            [self _submitResponseWithData:responseData requestType:requestType tag:tag];
        } else {
            NSString *errMsg = [NSString stringWithFormat:LKS_Localized(@"%@ doesn't have an instance method called %@."), NSStringFromClass(targerObj.class), text];
            [self _submitResponseWithError:LookinErrorMake(errMsg, @"") requestType:requestType tag:tag];
        }
        
    } else if (requestType == LookinPush_BringForwardScreenshotTask) {
        [[LKS_HierarchyDetailsHandler sharedInstance] bringForwardWithPackages:object];
    }
}

- (NSArray<NSString *> *)_methodNameListForClass:(Class)aClass {
    NSSet<NSString *> *prefixesToVoid = [NSSet setWithObjects:@"_", @"CA_", @"cpl", @"mf_", @"vs_", @"pep_", @"isNS", @"avkit_", @"PG_", @"px_", @"pl_", @"nsli_", @"pu_", @"pxg_", nil];
    NSMutableArray<NSString *> *array = [NSMutableArray array];
    
    Class currentClass = aClass;
    while (currentClass) {
        NSString *className = NSStringFromClass(currentClass);
        BOOL isSystemClass = ([className hasPrefix:@"UI"] || [className hasPrefix:@"CA"] || [className hasPrefix:@"NS"]);
        
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(currentClass, &methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            NSString *selName = NSStringFromSelector(method_getName(methods[i]));
            
            if (isSystemClass) {
                BOOL invalid = [prefixesToVoid lookin_any:^BOOL(NSString *prefix) {
                    return [selName hasPrefix:prefix];
                }];
                if (invalid) {
                    continue;
                }
            }
            if (selName.length && ![array containsObject:selName]) {
                [array addObject:selName];
            }
        }
        if (methods) free(methods);
        currentClass = [currentClass superclass];
    }

    return [array lookin_sortedArrayByStringLength];
}

- (void)_handleInvokeWithObject:(NSObject *)obj selector:(SEL)selector resultDescription:(NSString **)description resultObject:(LookinObject **)resultObject error:(NSError **)error {
    NSMethodSignature *signature = [obj methodSignatureForSelector:selector];
    if (signature.numberOfArguments > 2) {
        *error = LookinErrorMake(LKS_Localized(@"Lookin doesn't support invoking methods with arguments yet."), @"");
        return;
    }
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:obj];
    [invocation setSelector:selector];
    [invocation invoke];

    const char *returnType = [signature methodReturnType];
    
    
    if (strcmp(returnType, @encode(void)) == 0) {
        //void, do nothing

    } else if (strcmp(returnType, @encode(char)) == 0) {
        char charValue;
        [invocation getReturnValue:&charValue];
        *description = [NSString stringWithFormat:@"%@", @(charValue)];
        
    } else if (strcmp(returnType, @encode(int)) == 0) {
        int intValue;
        [invocation getReturnValue:&intValue];
        if (intValue == INT_MAX) {
            *description = @"INT_MAX";
        } else if (intValue == INT_MIN) {
            *description = @"INT_MIN";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(intValue)];
        }
        
    } else if (strcmp(returnType, @encode(short)) == 0) {
        short shortValue;
        [invocation getReturnValue:&shortValue];
        if (shortValue == SHRT_MAX) {
            *description = @"SHRT_MAX";
        } else if (shortValue == SHRT_MIN) {
            *description = @"SHRT_MIN";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(shortValue)];
        }
        
    } else if (strcmp(returnType, @encode(long)) == 0) {
        long longValue;
        [invocation getReturnValue:&longValue];
        if (longValue == NSNotFound) {
            *description = @"NSNotFound";
        } else if (longValue == LONG_MAX) {
            *description = @"LONG_MAX";
        } else if (longValue == LONG_MIN) {
            *description = @"LONG_MAX";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(longValue)];
        }
        
    } else if (strcmp(returnType, @encode(long long)) == 0) {
        long long longLongValue;
        [invocation getReturnValue:&longLongValue];
        if (longLongValue == LLONG_MAX) {
            *description = @"LLONG_MAX";
        } else if (longLongValue == LLONG_MIN) {
            *description = @"LLONG_MIN";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(longLongValue)];
        }
        
    } else if (strcmp(returnType, @encode(unsigned char)) == 0) {
        unsigned char ucharValue;
        [invocation getReturnValue:&ucharValue];
        if (ucharValue == UCHAR_MAX) {
            *description = @"UCHAR_MAX";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(ucharValue)];
        }
        
    } else if (strcmp(returnType, @encode(unsigned int)) == 0) {
        unsigned int uintValue;
        [invocation getReturnValue:&uintValue];
        if (uintValue == UINT_MAX) {
            *description = @"UINT_MAX";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(uintValue)];
        }
        
    } else if (strcmp(returnType, @encode(unsigned short)) == 0) {
        unsigned short ushortValue;
        [invocation getReturnValue:&ushortValue];
        if (ushortValue == USHRT_MAX) {
            *description = @"USHRT_MAX";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(ushortValue)];
        }
        
    } else if (strcmp(returnType, @encode(unsigned long)) == 0) {
        unsigned long ulongValue;
        [invocation getReturnValue:&ulongValue];
        if (ulongValue == ULONG_MAX) {
            *description = @"ULONG_MAX";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(ulongValue)];
        }
        
    } else if (strcmp(returnType, @encode(unsigned long long)) == 0) {
        unsigned long long ulongLongValue;
        [invocation getReturnValue:&ulongLongValue];
        if (ulongLongValue == ULONG_LONG_MAX) {
            *description = @"ULONG_LONG_MAX";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(ulongLongValue)];
        }
        
    } else if (strcmp(returnType, @encode(float)) == 0) {
        float floatValue;
        [invocation getReturnValue:&floatValue];
        if (floatValue == FLT_MAX) {
            *description = @"FLT_MAX";
        } else if (floatValue == FLT_MIN) {
            *description = @"FLT_MIN";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(floatValue)];
        }
        
    } else if (strcmp(returnType, @encode(double)) == 0) {
        double doubleValue;
        [invocation getReturnValue:&doubleValue];
        if (doubleValue == DBL_MAX) {
            *description = @"DBL_MAX";
        } else if (doubleValue == DBL_MIN) {
            *description = @"DBL_MIN";
        } else {
            *description = [NSString stringWithFormat:@"%@", @(doubleValue)];
        }
        
    } else if (strcmp(returnType, @encode(BOOL)) == 0) {
        BOOL boolValue;
        [invocation getReturnValue:&boolValue];
        *description = boolValue ? @"YES" : @"NO";
        
    } else if (strcmp(returnType, @encode(SEL)) == 0) {
        SEL selValue;
        [invocation getReturnValue:&selValue];
        *description = [NSString stringWithFormat:@"SEL(%@)", NSStringFromSelector(selValue)];
        
    } else if (strcmp(returnType, @encode(Class)) == 0) {
        Class classValue;
        [invocation getReturnValue:&classValue];
        *description = [NSString stringWithFormat:@"<%@>", NSStringFromClass(classValue)];
        
    } else if (strcmp(returnType, @encode(CGPoint)) == 0) {
        CGPoint targetValue;
        [invocation getReturnValue:&targetValue];
        *description = NSStringFromCGPoint(targetValue);

    } else if (strcmp(returnType, @encode(CGVector)) == 0) {
        CGVector targetValue;
        [invocation getReturnValue:&targetValue];
        *description = NSStringFromCGVector(targetValue);

    } else if (strcmp(returnType, @encode(CGSize)) == 0) {
        CGSize targetValue;
        [invocation getReturnValue:&targetValue];
        *description = NSStringFromCGSize(targetValue);

    } else if (strcmp(returnType, @encode(CGRect)) == 0) {
        CGRect rectValue;
        [invocation getReturnValue:&rectValue];
        *description = NSStringFromCGRect(rectValue);
        
    } else if (strcmp(returnType, @encode(CGAffineTransform)) == 0) {
        CGAffineTransform rectValue;
        [invocation getReturnValue:&rectValue];
        *description = NSStringFromCGAffineTransform(rectValue);
        
    } else if (strcmp(returnType, @encode(UIEdgeInsets)) == 0) {
        UIEdgeInsets targetValue;
        [invocation getReturnValue:&targetValue];
        *description = NSStringFromUIEdgeInsets(targetValue);
        
    } else if (strcmp(returnType, @encode(UIOffset)) == 0) {
        UIOffset targetValue;
        [invocation getReturnValue:&targetValue];
        *description = NSStringFromUIOffset(targetValue);
        
    } else {
        if (@available(iOS 11.0, *)) {
            if (strcmp(returnType, @encode(NSDirectionalEdgeInsets)) == 0) {
                NSDirectionalEdgeInsets targetValue;
                [invocation getReturnValue:&targetValue];
                *description = NSStringFromDirectionalEdgeInsets(targetValue);
                return;
            }
        }
        
        NSString *argType_string = [[NSString alloc] lookin_safeInitWithUTF8String:returnType];
        if ([argType_string hasPrefix:@"@"] || [argType_string hasPrefix:@"^{"]) {
            __unsafe_unretained id returnObjValue;
            [invocation getReturnValue:&returnObjValue];
            
            if (returnObjValue) {
                *description = [NSString stringWithFormat:@"%@", returnObjValue];
                
                LookinObject *parsedLookinObj = [LookinObject instanceWithObject:returnObjValue];
                *resultObject = parsedLookinObj;
            } else {
                *description = @"nil";
            }
        } else {
            *description = [NSString stringWithFormat:LKS_Localized(@"%@ was invoked successfully, but Lookin can't parse the return value:%@"), NSStringFromSelector(selector), argType_string];
        }
    }
}

- (void)_submitResponseWithError:(NSError *)error requestType:(uint32_t)requestType tag:(uint32_t)tag {
    LookinConnectionResponseAttachment *attachment = [LookinConnectionResponseAttachment new];
    attachment.error = error;
    [[LKS_ConnectionManager sharedInstance] respond:attachment requestType:requestType tag:tag];
}

- (void)_submitResponseWithData:(NSObject *)data requestType:(uint32_t)requestType tag:(uint32_t)tag {
    LookinConnectionResponseAttachment *attachment = [LookinConnectionResponseAttachment new];
    attachment.data = data;
    [[LKS_ConnectionManager sharedInstance] respond:attachment requestType:requestType tag:tag];
}

@end
