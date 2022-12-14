//
//  LLNetworkAccessibility.m
//  Created by lanlinxl on 12/07/2022.
//  Copyright (c) 2022 lanlinxl. All rights reserved.

#import "LLNetworkAccessibility.h"
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTCellularData.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <arpa/inet.h>


NSString * const LLNetworkStateChangedNotification = @"LLNetworkAccessibilityChangedNotification";

typedef NS_ENUM(NSInteger, NetworkType) {
    unknowned ,
    offline   ,
    wifi      ,
    cellular  ,
};

@interface LLNetworkAccessibility(){
    SCNetworkReachabilityRef _reachabilityRef;
    CTCellularData *_cellularData;
    NSMutableArray *_becomeActiveCallbacks;
    AuthType _previousState;
    UIAlertController *_alertController;
    BOOL _automaticallyAlert;
    ReachabilityUpdateCallBackBlock _reachabilityUpdateCallBackBlock;
    BOOL _checkingWithBecomeActive;
}

@end


@implementation LLNetworkAccessibility


#pragma mark - Public

+ (void)start {
    [[self sharedInstance] setupNetworkAccessibility];
}

+ (void)stop {
    [[self sharedInstance] cleanNetworkAccessibility];
}

+ (void)setAlertEnable:(BOOL)setAlertEnable {
    [self sharedInstance]->_automaticallyAlert = setAlertEnable;
}


+ (void)reachabilityUpdateCallBack:(void (^)(AuthType))block {
    [[self sharedInstance] monitorNetworkAccessibleStateWithCompletionBlock:block];
}

+ (AuthType)currentState {
    return [[self sharedInstance] currentState];
}


#pragma mark - Public entity method
+ (LLNetworkAccessibility *)sharedInstance {
    static LLNetworkAccessibility * instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}
- (instancetype)init {
    if (self = [super init]) { }
    return self;
}

- (void)monitorNetworkAccessibleStateWithCompletionBlock:(void (^)(AuthType))block {
    _reachabilityUpdateCallBackBlock = [block copy];
}

- (AuthType)currentState {
    return _previousState;
}


#pragma mark - setAccessibility
- (void)setupNetworkAccessibility {
    if ([self isSimulator]) {
        // ???????????????????????????
        [self notiWithAccessibleState: available];
        return;
    }
    if (_reachabilityRef || _cellularData) {
        return;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    _reachabilityRef = SCNetworkReachabilityCreateWithName(NULL, "223.5.5.5");
    // ????????????????????????????????????????????????
    SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    _becomeActiveCallbacks = [NSMutableArray array];
    
    NSString * firstRunFlag = @"LLNetworkAccessibilityFirstRunFlag";
    BOOL value = [[NSUserDefaults standardUserDefaults] boolForKey:firstRunFlag];
    if (value){
        [self startReachabilityListener];
        [self startCellularDataListener];
        
    }else {
        // ??????????????????
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:firstRunFlag];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startReachabilityListener];
            [self startCellularDataListener];
        });
    }
}

- (BOOL)isSimulator {
#if TARGET_OS_SIMULATOR
    BOOL isSimulator = YES;
#else
    BOOL isSimulator = NO;
#endif
    return isSimulator;
}


#pragma mark - Check Accessibility
- (void)startCheck {
    /* ?????? currentReachable ???????????????????????? YES ????????????
     1. ??????????????? ???WALN ????????????????????????????????????????????????????????????
     2. ??????????????? ???WALN???????????? WALN ??????????????????
     ???????????????????????????????????????????????? ZYNetworkAccessible
     **/
    if ([self currentReachable]) {
        return [self notiWithAccessibleState:available];
    }
    
    CTCellularDataRestrictedState state = _cellularData.restrictedState;
    switch (state) {
        case kCTCellularDataRestricted: {// ?????? API ?????? ???????????????????????????
            // ?????????????????????????????? ??? WLAN ???????????????????????? ?????????????????????
            if ([self isUseWifiConnect] || [self isUseWWANConnect]) {
                [self notiWithAccessibleState: restricted];
            }else {
                [self notiWithAccessibleState: unknown];
            }
            break;
        }
        case kCTCellularDataNotRestricted: // ?????? API ?????????????????????????????????????????????????????? Wi-Fi ??????????????????
            [self notiWithAccessibleState:available];
            break;
        case kCTCellularDataRestrictedStateUnknown: {
            // CTCellularData ????????????????????????????????????????????? kCTCellularDataRestrictedStateUnknown ???????????????????????????
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self startCheck];
            });
            break;
        }
        default:
            break;
    };
}

// ???????????????????????????????????????
- (BOOL)currentReachable {
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(self->_reachabilityRef, &flags)) {
        if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
            return NO;
        } else {
            return YES;
        }
    }
    return NO;
}


// ??????????????????
- (void)notiWithAccessibleState:(AuthType)state {
    if (_automaticallyAlert) {
        if (state == restricted) {
                [self showNetworkRestrictedAlert];
        } else {
            [self hideNetworkRestrictedAlert];
        }
    }
    
    if (state != _previousState) {
        _previousState = state;
        if (_reachabilityUpdateCallBackBlock) {
            _reachabilityUpdateCallBackBlock(state);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:LLNetworkStateChangedNotification object:nil];
    }
}

#pragma mark - ??????????????????
static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
    LLNetworkAccessibility *networkAccessibility = (__bridge LLNetworkAccessibility *)info;
    if (![networkAccessibility isKindOfClass: [LLNetworkAccessibility class]]) {
        return;
    }
    [networkAccessibility startCheck];
}

// ??????????????? Wi-Fi ????????? ????????????????????????????????????????????? Wi-Fi?????????????????????????????????????????????????????????????????????????????????
- (void)startReachabilityListener{
    SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    if (SCNetworkReachabilitySetCallback(_reachabilityRef, ReachabilityCallback, &context)) {
        SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    }
}

- (void)startCellularDataListener {
    __weak __typeof(self)weakSelf = self;
    self->_cellularData = [[CTCellularData alloc] init];
    self->_cellularData.cellularDataRestrictionDidUpdateNotifier = ^(CTCellularDataRestrictedState state) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf startCheck];
        });
    };
}

/**
 ??????????????????????????????????????????3G???4G???5G???
 */
-(BOOL)isUseWWANConnect{
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(self->_reachabilityRef, &flags)) {
        return (flags & kSCNetworkReachabilityFlagsIsWWAN);
    }
    return NO;
}

/**
 ?????????????????????wifi??????
 */
- (BOOL)isUseWifiConnect {
    @try {
        NSString *ipAddress;
        struct ifaddrs *interfaces;
        struct ifaddrs *temp;
        int Status = 0;
        Status = getifaddrs(&interfaces);
        if (Status == 0) {
            temp = interfaces;
            while(temp != NULL) {
                if(temp->ifa_addr->sa_family == AF_INET) {
                    if([[NSString stringWithUTF8String:temp->ifa_name] isEqualToString:@"en0"]) {
                        ipAddress = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
                    }
                }
                temp = temp->ifa_next;
            }
        }
        freeifaddrs(interfaces);
        if (ipAddress == nil || ipAddress.length <= 0) {
            return false;
        }
        NSLog(@"wifiAddress: %@",ipAddress);
        return (ipAddress.length > 0);
    }
    @catch (NSException *exception) {
        return false;
    }
}


#pragma mark - ?????????/????????????

- (void)applicationWillResignActive {
    [self hideNetworkRestrictedAlert];
    _checkingWithBecomeActive = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(becomeActive) object:nil];
}

- (void)applicationDidBecomeActive {
    if (_checkingWithBecomeActive) {
        _checkingWithBecomeActive = NO;
        [self performSelector:@selector(becomeActive) withObject:nil afterDelay:1.5 inModes:@[NSRunLoopCommonModes]];
    }
}

- (void)becomeActive {
    [self startReachabilityListener];
    [self startCellularDataListener];
}



// ??????
- (void)cleanNetworkAccessibility {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _cellularData.cellularDataRestrictionDidUpdateNotifier = nil;
    _cellularData = nil;
    SCNetworkReachabilityUnscheduleFromRunLoop(_reachabilityRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    _reachabilityRef = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(becomeActive) object:nil];
    [self hideNetworkRestrictedAlert];
    [_becomeActiveCallbacks removeAllObjects];
    _becomeActiveCallbacks = nil;
    _previousState = checking;
}



#pragma mark - ????????????
- (void)showNetworkRestrictedAlert {
    if (self.alertController.presentingViewController == nil && ![self.alertController isBeingPresented]) {
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:self.alertController animated:YES completion:nil];
    }
}

- (void)hideNetworkRestrictedAlert {
    [_alertController dismissViewControllerAnimated:YES completion:nil];
}

- (UIAlertController *)alertController {
    if (!_alertController) {
        _alertController = [UIAlertController alertControllerWithTitle:@"??????????????????" message:@"???????????????????????????????????????????????????????????????" preferredStyle:UIAlertControllerStyleAlert];
        
        [_alertController addAction:[UIAlertAction actionWithTitle:@"??????" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self hideNetworkRestrictedAlert];
        }]];
        
        [_alertController addAction:[UIAlertAction actionWithTitle:@"??????" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
                [[UIApplication sharedApplication] openURL:settingsURL options: @{} completionHandler:nil];
            }
        }]];
    }
    return _alertController;
}

@end
