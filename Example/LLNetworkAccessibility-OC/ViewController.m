//
//  ViewController.m
//  LLNetworkAccessibility-OC
//
//  Created by lanlinxl on 12/08/2022.
//  Copyright (c) 2022 lanlinxl. All rights reserved.
//

#import "ViewController.h"
#import "LLNetworkAccessibility.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UILabel * label = [[UILabel alloc] init];
    [self.view addSubview:label];
    label.textColor = [UIColor blueColor];
    label.font = [UIFont systemFontOfSize:18 weight: UIFontWeightMedium];
    label.frame = CGRectMake(150, 120, 100, 30);
    
    UIButton * button = [UIButton buttonWithType: UIButtonTypeSystem];
    [button setTitle:@"设置按钮" forState:UIControlStateNormal];
    [self.view addSubview:button];
    button.frame = CGRectMake(150, 180, 100, 30);
    [button addTarget:self action:@selector(buttonClick) forControlEvents:UIControlEventTouchUpInside];
    
    [LLNetworkAccessibility start];
    [LLNetworkAccessibility setAlertEnable:true];
    [LLNetworkAccessibility reachabilityUpdateCallBack:^(AuthType state) {
        switch (state) {
            case available:
                label.text = @"网络可用";
                break;
            case restricted:
                label.text = @"网络未授权";
                break;
            case unknown:
                label.text = @"飞行模式";
                break;
            default:
                break;
        }
    }];
}

- (void)buttonClick {
    NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
        [[UIApplication sharedApplication] openURL:settingsURL options: @{} completionHandler:nil];
    }
}


@end
