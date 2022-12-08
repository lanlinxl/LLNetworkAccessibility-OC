//
//  LLNetworkAccessibility.h
//
//  Created by lanlinxl on 12/07/2022.
//  Copyright (c) 2022 lanlinxl. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const LLNetworkStateChangedNotification;

typedef NS_ENUM(NSUInteger, AuthType) {
    checking  = 0,
    unknown      ,
    available    ,
    restricted   ,
};

typedef void (^ReachabilityUpdateCallBackBlock)(AuthType state);

@interface LLNetworkAccessibility : NSObject

/**
 开启 LLNetworkAccessibility
 */
+ (void)start;

/**
 停止 LLNetworkAccessibility
 */
+ (void)stop;

/**
 当判断网络状态为 restricted 时，提示用户开启网络权限
 */
+ (void)setAlertEnable:(BOOL)setAlertEnable;

/**
  通过 block 方式监控网络权限变化。
 */
+ (void)reachabilityUpdateCallBack:(void (^)(AuthType))block;

/**
 返回的是最近一次的网络状态检查结果，若距离上一次检测结果短时间内网络授权状态发生变化，该值可能会不准确。
 */
+ (AuthType)currentState;


@end
