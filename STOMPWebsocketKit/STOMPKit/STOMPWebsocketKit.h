//
//  STOMPWebsocketKit.h
//  KitchenWarning
//
//  Created by arges on 2019/7/31.
//  Copyright © 2019年 ArgesYao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const KWSocketErrorDomain = @"KWSocketErrorDomain";

typedef NS_ENUM(NSInteger, KWSocketError) {
    KWSocketErrorDefault = 100000 << 0,   // STOMP默认的command Error
    KWSocketErrorUnkwon =  100000 << 1,   // command未知的 Error
    KWSocketErrorClosed = 100000 << 2,    // Socket关闭导致的Error
};

typedef NS_ENUM(NSUInteger, KWCommandType) {
    //Client
    KWCommandTypeConnect,
    KWCommandTypeDisconnect,
    KWCommandTypeBegin,
    KWCommandTypeSubscribe,
    KWCommandTypeUnsubscribe,
    KWCommandTypeSend,
    KWCommandTypeAck,
    KWCommandTypeNack,
    KWCommandTypeAbort,
    KWCommandTypeCommit,
    //SERVER
    KWCommandTypeConnected,
    KWCommandTypeError,
    KWCommandTypeMessage,
    KWCommandTypeReceipt,

};

UIKIT_EXTERN NSString * _commandKey(KWCommandType type);

@class KWSocketDataFrame;

typedef void (^CompleteHandlerBlock)(KWSocketDataFrame * __nullable , NSError * __nullable);
typedef void (^FailureHandlerBlock)(NSError *);

@interface KWSocketDataFrame : NSObject

@property (nonatomic, copy, readonly) NSString *command;
@property (nonatomic, copy, readonly) NSDictionary *header;
@property (nonatomic, copy, readonly) NSString *data;
/*!
 * @brief 发送给Socket的字节数据
 */
@property (nonatomic, copy, readonly) NSData *socketSendData;

@end

@interface STOMPWebsocketKit : NSObject

/*!
 * @brief Socket 状态、数据回调
 */
@property (nonatomic, copy) CompleteHandlerBlock successHandlerBlock;
@property (nonatomic, copy) FailureHandlerBlock  failureHandlerBlock;
@property (nonatomic, copy) FailureHandlerBlock disconnectHandlerBlock;

/*!
 * @brief Socket 是否在连接状态
 */
@property (nonatomic, assign, readonly) BOOL isConnect;
/*!
 * Socket URL
 */
@property (nonatomic, strong, readonly) NSURL *url;

/*! 是否开启客户端心跳ping  默认 YES 开启
 */
@property (nonatomic, assign) BOOL isEnableClientPing;

/*! 是否开启服务器端心跳pong 默认 NO 关闭
 */
@property (nonatomic, assign) BOOL isEnableServerPong;

+ (instancetype)shareInstance;

- (void)initWithUtl:(NSURL *)url;
/*!
 * @brief 初始化 Socket 信息
 */
- (void)initSocketWithHost:(NSString *)host
                      port:(NSUInteger)port scheme:(NSString *)scheme;

#pragma mark - CONNECT

/*!
 * @brief header传入头部字段信息
 * @discussion header : header信息 (@"Authorization" : [KWAPPServer shareInstance].loginModel.accessToken)
 */
- (void)connectToSocketWithHeader:(NSDictionary * __nullable)header;

#pragma mark - ACK

/*!
 * @brief ACK
 */
- (void)sendAck;
/*!
 * @brief ACK Header
 */
- (void)sendAckWithHeader:(NSDictionary * __nullable)header;
/*!
 * @brief NACK
 */
- (void)sendNack;
/*!
 * @brief NACK Header
 */
- (void)sendNackWithHeader:(NSDictionary * __nullable)header;

#pragma mark - SUBSCRIBE

/*!
 * @brief 订阅Socket消息推送
 * @discussion destination 订阅的服务路径
 */
- (void)sendSubscribeWithDestination:(NSString *)destination
                             handler:(CompleteHandlerBlock)handler;

/*!
 * @brief 订阅Socket消息推送
 * @discussion destination 订阅的服务路径 header header信息
 */
- (void)sendSubscribeWithDestination:(NSString *)destination
                              header:(NSDictionary * __nullable)header
                             handler:(CompleteHandlerBlock __nullable)handler;
/*!
 * @brief 取消订阅Socket消息推送
 * @discussion headerId 订阅的服务ID
 */
- (void)sendUnsubscribeWithHeaderId:(NSString *)headerId;
/*!
 * @brief 取消订阅Socket消息推送
 * @discussion header 头部信息
 */
- (void)sendUnsubscribeWithHeader:(NSDictionary *)header;

#pragma mark - BEGIN

- (void)sendBegin;

- (void)sendBeginWithIdentifier:(NSString *)identifier;

#pragma mark - COMMIT

- (void)commitWithIdentifier:(NSString *)identifier;

- (void)abortWithIdentifier:(NSString *)identifier;

#pragma mark - DESTINATION

- (void)sendFrameWithDestination:(NSString *)destination
                            data:(NSString *)data;

- (void)sendFrameWithDestination:(NSString *)destination
                          header:(NSDictionary *)header data:(NSString *)data;

#pragma mark - DISCONNECT

/*!
 * @brief DISCONNECT
 */
- (void)sendDisconnect;
/*!
 * @brief 断开Socket连接 
 */
- (void)sendDisconnectWithHandler:(FailureHandlerBlock __nullable)handler;

@end

NS_ASSUME_NONNULL_END
