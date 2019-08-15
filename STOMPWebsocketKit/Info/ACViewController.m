//
//  ViewController.m
//  STOMPWebsocketKit
//
//  Created by arges on 2019/8/15.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import "ACViewController.h"

@interface ACViewController ()

@end

@implementation ACViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    //开启Socket服务
        NSDictionary *header = @{ @"Authorization" : @"eyJhbGciOiJIUzI1NiJ9.eyJpYXQiOjE1NjU4MzAwODMsImlzcyI6ImtpdGNoZW5famF2YSIsInN1YiI6ImFjY2Vzc190b2tlbiIsImp0aSI6IjE1NjU4MzAwODMwNDEuMiIsImV4cCI6MTU2NzEyNjA4MywiYnVzaW5lc3NJZCI6MSwiaWQiOjIsInR5cGUiOjF9.SU2UNICgdIvtZ326vZTN6Y3FDxe5fxEzGgds_55WXrc" };
        NSString *businessId = @"0";
        [[STOMPWebsocketKit shareInstance] setDisconnectHandlerBlock:^(NSError * error) {
    
        }];
        [[STOMPWebsocketKit shareInstance] setFailureHandlerBlock:^(NSError * error) {
    
    
        }];
    
        [[STOMPWebsocketKit shareInstance] setSuccessHandlerBlock:^(KWSocketDataFrame * dataFrame, NSError * error) {
            if ([dataFrame.command isEqualToString:_commandKey(KWCommandTypeConnected)]) {
                NSString *socketService = [NSString stringWithFormat:@"/topic/v1/school/notifications/updates/%@", businessId];
                [[STOMPWebsocketKit shareInstance] sendSubscribeWithDestination:socketService header:header handler:^(KWSocketDataFrame * dataFrame, NSError * error) {
    
    
                }];
                [[STOMPWebsocketKit shareInstance] sendSubscribeWithDestination:@"/user/queue/v1/notifications/updates" header:header handler:^(KWSocketDataFrame * dataFrame, NSError * error) {
    
                }];
            }
        }];
        NSURL *websocketUrl = [NSURL URLWithString:[NSString stringWithFormat:@"ws://%@:%@/masc_kitchen/api/socket", @"192.168.3.34", @(8090)]];
        [[STOMPWebsocketKit shareInstance] initWithUtl:websocketUrl];
    ////    [[STOMPWebsocketKit shareInstance] initSocketWithHost:@"localhost" port:61613 scheme:@""];
        [[STOMPWebsocketKit shareInstance] connectToSocketWithHeader:header];
}


@end
