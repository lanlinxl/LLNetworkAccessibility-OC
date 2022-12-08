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
        // 模拟器检测默认通过
        [self notiWithAccessibleState: available];
        return;
    }
    if (_reachabilityRef || _cellularData) {
        return;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    _reachabilityRef = SCNetworkReachabilityCreateWithName(NULL, "223.5.5.5");
    // 此行代码会触发系统弹出权限询问框
    SCNetworkReachabilityScheduleWithRunLoop(_reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    _becomeActiveCallbacks = [NSMutableArray array];
    
    NSString * firstRunFlag = @"LLNetworkAccessibilityFirstRunFlag";
    BOOL value = [[NSUserDefaults standardUserDefaults] boolForKey:firstRunFlag];
    if (value){
        [self startReachabilityListener];
        [self startCellularDataListener];
        
    }else {
        // 首次进入应用
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
    /* 先用 currentReachable 判断，若返回的为 YES 则说明：
     1. 用户选择了 「WALN 与蜂窝移动网」并处于其中一种网络环境下。
     2. 用户选择了 「WALN」并处于 WALN 网络环境下。
     此时是有网络访问权限的，直接返回 ZYNetworkAccessible
     **/
    if ([self currentReachable]) {
        return [self notiWithAccessibleState:available];
    }
    
    CTCellularDataRestrictedState state = _cellularData.restrictedState;
    switch (state) {
        case kCTCellularDataRestricted: {// 系统 API 返回 无蜂窝数据访问权限
            // 若用户是通过蜂窝数据 或 WLAN 上网，走到这里来 说明权限被关闭
            if ([self isUseWifiConnect] || [self isUseWWANConnect]) {
                [self notiWithAccessibleState: restricted];
            }else {
                [self notiWithAccessibleState: unknown];
            }
            break;
        }
        case kCTCellularDataNotRestricted: // 系统 API 访问有有蜂窝数据访问权限，那就必定有 Wi-Fi 数据访问权限
            [self notiWithAccessibleState:available];
            break;
        case kCTCellularDataRestrictedStateUnknown: {
            // CTCellularData 刚开始初始化的时候，可能会拿到 kCTCellularDataRestrictedStateUnknown 延迟一下再试就好了
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self startCheck];
            });
            break;
        }
        default:
            break;
    };
}

// 当前授权的网络权限是否可用
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


// 通知授权状态
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

#pragma mark - 相关状态监听
static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
    LLNetworkAccessibility *networkAccessibility = (__bridge LLNetworkAccessibility *)info;
    if (![networkAccessibility isKindOfClass: [LLNetworkAccessibility class]]) {
        return;
    }
    [networkAccessibility startCheck];
}

// 监听用户从 Wi-Fi 切换到 蜂窝数据，或者从蜂窝数据切换到 Wi-Fi，另外当从授权到未授权，或者未授权到授权也会调用该方法
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
 判断是否在使用蜂窝网络连接（3G、4G、5G）
 */
-(BOOL)isUseWWANConnect{
    SCNetworkReachabilityFlags flags;
    if (SCNetworkReachabilityGetFlags(self->_reachabilityRef, &flags)) {
        return (flags & kSCNetworkReachabilityFlagsIsWWAN);
    }
    return NO;
}

/**
 判断是否在使用wifi网络
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


#pragma mark - 进入前/后台处理

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



// 清除
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



#pragma mark - 提示弹框
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
        _alertController = [UIAlertController alertControllerWithTitle:@"网络连接失败" message:@"检测到网络权限未开启，您可以点击设置去开启" preferredStyle:UIAlertControllerStyleAlert];
        
        [_alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self hideNetworkRestrictedAlert];
        }]];
        
        [_alertController addAction:[UIAlertAction actionWithTitle:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            if([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
                [[UIApplication sharedApplication] openURL:settingsURL options: @{} completionHandler:nil];
            }
        }]];
    }
    return _alertController;
}

@end
