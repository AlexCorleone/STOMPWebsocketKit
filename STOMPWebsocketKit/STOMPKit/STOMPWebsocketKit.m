//
//  STOMPWebsocketKit.m
//  KitchenWarning
//
//  Created by arges on 2019/7/31.
//  Copyright © 2019年 ArgesYao. All rights reserved.
//

#import "STOMPWebsocketKit.h"
#import <SocketRocket.h>
#import "STOMPHeader.h"

/*
 * STOMP http://stomp.github.io/stomp-specification-1.1.html#Client_Frames
 * Srtandard Hearders
 *  content-length :
 *  content-type :
 *  subscription :
 *  destination :
 *  receipt-id :
 
 CONNECT 1.1 MUST SET
 *  accept-version : The versions of the STOMP protocol the client supports.
 *  host : The name of a virtual host that the client wishes to connect to.
      MAY SET
 *  login : The user id used to authenticate against a secured STOMP server.
 *  passcode : The password used to authenticate against a secured STOMP server.
 
 
 * Heart-beating
 *  heart-beat :
 CONNECT
 heart-beat:<cx>,<cy>
 
 CONNECTED:
 heart-beat:<sx>,<sy>
 */

#define kAcceptVersion @"1.0,1.1"

static NSString * kFrameLineFeed = @"\x0A";
static NSString * kFrameNullChar = @"\x00";
static NSString * kFrameHeaderSeparator = @":";

NSString * _commandKey(KWCommandType type) {
     NSDictionary  *socketCommand = @{@(KWCommandTypeConnect)     : @"CONNECT",
                                      @(KWCommandTypeSend)        : @"SEND",
                                      @(KWCommandTypeSubscribe)   : @"SUBSCRIBE",
                                      @(KWCommandTypeUnsubscribe) : @"UNSUBSCRIBE",
                                      @(KWCommandTypeBegin)       : @"BEGIN",
                                      @(KWCommandTypeCommit)      : @"COMMIT",
                                      @(KWCommandTypeAbort)       : @"ABORT",
                                      @(KWCommandTypeAck)         : @"ACK",
                                      @(KWCommandTypeNack)        : @"NACK",
                                      @(KWCommandTypeDisconnect)  : @"DISCONNECT",
                                      //Server
                                      @(KWCommandTypeConnected)   : @"CONNECTED",
                                      @(KWCommandTypeError)       : @"ERROR",
                                      @(KWCommandTypeMessage)     : @"MESSAGE",
                                      @(KWCommandTypeReceipt)     : @"RECEIPT",
                                      };
    NSString *commmandKey = socketCommand[@(type)];
    return commmandKey;
}

@interface KWSocketDataFrame ()

@property (nonatomic, copy) NSString *command;
@property (nonatomic, copy) NSDictionary *header;
@property (nonatomic, copy) NSString *data;

- (id)initWithCommand:(NSString *)command
               header:(NSDictionary *)header
                 data:(NSString *)data;
@end

@implementation KWSocketDataFrame

- (id)initWithCommand:(NSString *)command
               header:(NSDictionary *)header
                 data:(NSString *)data {
    if (self = [super init]) {
        self.command = command;
        self.header = header;
        self.data = data;
    }
    return self;
}

#pragma mark - Setter && Getter

- (NSData *)socketSendData {
    return [[self description] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)description {
    NSMutableString *frame = [NSMutableString stringWithString: [self.command stringByAppendingString:kFrameLineFeed]];
    for (id key in self.header) {
        [frame appendString:[NSString stringWithFormat:@"%@%@%@%@", key, kFrameHeaderSeparator, self.header[key], kFrameLineFeed]];
    }
    [frame appendString:kFrameLineFeed];
    if (self.data) {
        [frame appendString:self.data];
    }
    [frame appendString:kFrameNullChar];
    return frame;
}

@end

@interface STOMPWebsocketKit()<SRWebSocketDelegate>

@property (nonatomic,assign) BOOL isConnect;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, retain) NSMutableDictionary *subscriptions;

/*!
 * Socket对象
 */
@property (nonatomic, strong) SRWebSocket *SRsocket;
/*!
 * Socket URL
 */
@property (nonatomic, strong) NSURL *url;
/*!
 * 服务器地址
 */
@property (nonatomic, copy) NSString *host;
/*!
 * 端口号
 */
@property (nonatomic, assign) NSUInteger port;
/*!
 * Socket 请求的Header
 */
@property (nonatomic, strong) NSDictionary * connectHeader;
/*!
 * 心跳
 */
@property (nonatomic, strong) NSTimer *pingTimer;
@property (nonatomic, strong) NSTimer *pongTimer;
@property (nonatomic, copy) NSString *clientHeartBeat;
@property (nonatomic, strong) NSThread *timerThread;

@end

@implementation STOMPWebsocketKit

long long identifierCount;
CFAbsoluteTime headerBeatTime;

#pragma mark - Life Cycle

+ (instancetype)new {
    return [STOMPWebsocketKit shareInstance];
}

static STOMPWebsocketKit *socketManager = nil;
+ (instancetype)alloc {
    socketManager = [super alloc];
    if (socketManager) {
    }
    return socketManager;
}

- (instancetype)init {
    socketManager = [super init];
    if (socketManager) {
        
    }
    return socketManager;
}

- (id)mutableCopy {
    return socketManager;
}

#pragma mark - Public

+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        socketManager = [[STOMPWebsocketKit alloc] init];
        socketManager.clientHeartBeat = @"5000,10000";
        socketManager.isEnableClientPing = YES;
        socketManager.isEnableServerPong = NO;
    });
    return socketManager;
}

- (void)initWithUtl:(NSURL *)url {
    self.url = url;
    NSString *host = self.url.host;
    NSNumber *port = self.url.port;
    [self initSocketWithHost:host port:port.integerValue scheme:self.url.scheme];
}

- (void)initSocketWithHost:(NSString *)host
                      port:(NSUInteger)port scheme:(NSString *)scheme  {
    self.host = host;
    self.port = port;
    scheme = (scheme && scheme.length > 0) ? scheme : @"http";
    if (!self.url) {
        self.url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:%@", scheme, self.host, @(self.port)]];
    }
}

#pragma mark - CONNECT

- (void)connectToSocketWithHeader:(NSDictionary *)header {
    
    self.connectHeader = header;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url];
    [request setAllHTTPHeaderFields:header];
    self.SRsocket = [[SRWebSocket alloc] initWithURLRequest:request protocols:@[]];
    [self.SRsocket setDelegateDispatchQueue:self.socketQueue];
    self.SRsocket.delegate = self;
    [self.SRsocket open];
}

#pragma mark - ACK

- (void)sendAck {
    [self sendAckWithHeader:nil];
}

- (void)sendAckWithHeader:(NSDictionary *)header {
    [self sendFrameWithCommand:_commandKey(KWCommandTypeAck)
                       header:header data:nil];
}

- (void)sendNack {
    [self sendNackWithHeader:nil];
}

- (void)sendNackWithHeader:(NSDictionary *)header {
    [self sendFrameWithCommand:_commandKey(KWCommandTypeNack)
                       header:header data:nil];
}

#pragma mark - SUBSCRIBE

- (void)sendSubscribeWithDestination:(NSString *)destination handler:(CompleteHandlerBlock)handler {
    [self sendSubscribeWithDestination:destination
                                header:nil handler:handler];
}

- (void)sendSubscribeWithDestination:(NSString *)destination
                              header:(NSDictionary *)header handler:(CompleteHandlerBlock)handler {
    NSAssert(destination, @"subscribe destination not null");
        NSMutableDictionary *sendHeader = [[NSMutableDictionary alloc] initWithDictionary:header];
        [sendHeader setValue:destination forKey:@"destination"];
        NSString *identifier = header[@"id"];
        if (!identifier) {
            identifier = [NSString stringWithFormat:@"sub-%lld", identifierCount++];
            [sendHeader setValue:identifier forKey:@"id"];
        }
        self.subscriptions[identifier] = [handler copy];
        [self sendFrameWithCommand:_commandKey(KWCommandTypeSubscribe) header:sendHeader data:nil];
}

- (void)sendUnsubscribeWithHeaderId:(NSString *)headerId {
    NSDictionary *header = nil;
    if (headerId) {
       header = @{@"id" : headerId};
    }
    STLog(@"sockect header identifier : %@", headerId);
    [self sendUnsubscribeWithHeader:header];
}

- (void)sendUnsubscribeWithHeader:(NSDictionary *)header {
    [self sendFrameWithCommand:_commandKey(KWCommandTypeUnsubscribe)
                        header:header data:nil];
}

#pragma mark - BEGIN

- (void)sendBegin {
    NSString *identifier = [NSString stringWithFormat:@"tx-%lld", identifierCount++];
    [self sendBeginWithIdentifier:identifier];
}

- (void)sendBeginWithIdentifier:(NSString *)identifier {
    NSAssert(identifier, @"begin identifier not null");
    [self sendFrameWithCommand:_commandKey(KWCommandTypeBegin)
                        header:@{@"transaction" : identifier} data:nil];
}

#pragma mark - COMMIT

- (void)commitWithIdentifier:(NSString *)identifier {
    NSAssert(identifier, @"commit identifier not null");
    [self sendFrameWithCommand:_commandKey(KWCommandTypeCommit)
                       header:@{ @"transaction" : identifier } data:nil];
}

- (void)abortWithIdentifier:(NSString *)identifier {
    NSAssert(identifier, @"commit identifier not null");
    [self sendFrameWithCommand:_commandKey(KWCommandTypeAbort)
                              header:@{ @"transaction" : identifier } data:nil];
}

#pragma mark - DESTINATION

- (void)sendFrameWithDestination:(NSString *)destination
                            data:(NSString *)data {
    [self sendFrameWithCommand:destination header:nil data:data];
}

- (void)sendFrameWithDestination:(NSString *)destination
                          header:(NSDictionary *)header data:(NSString *)data {
    NSAssert(destination, @"send destination not null");
    NSMutableDictionary *sendHeader = [NSMutableDictionary dictionaryWithDictionary:header];
    [sendHeader setValue:destination forKey:@"destination"];
    [sendHeader setValue:@([data length]).stringValue forKey:@"content-length"];
    [self sendFrameWithCommand:_commandKey(KWCommandTypeSend)
                        header:header data:data];
}

#pragma mark - DISCONNECT

- (void)sendDisconnect {
    [self sendDisconnectWithHandler:nil];
}

- (void)sendDisconnectWithHandler:(FailureHandlerBlock)handler {
    self.disconnectHandlerBlock = handler;
    [self sendFrameWithCommand:_commandKey(KWCommandTypeDisconnect) header:nil data:nil];
    [self.subscriptions removeAllObjects];
    [self.SRsocket close];
    [self.pingTimer invalidate];
    self.pingTimer = nil;
}

#pragma mark - Private

- (void)sendConnectCommand {
    NSMutableDictionary *sendHeader = [self.connectHeader mutableCopy];
    if (sendHeader) {
        [sendHeader setValue:kAcceptVersion forKey:@"accept-version"];
        if (self.host) {
            [sendHeader setValue:self.host forKey:@"host"];
        }
        [sendHeader setValue:@"5000,1000" forKey:@"heart-beat"];
    }
    [self sendFrameWithCommand:_commandKey(KWCommandTypeConnect)
                        header:sendHeader
                          data:nil];
}

- (void)configSocketWithConnectFrame:(KWSocketDataFrame *)dataFrame {
    if (dataFrame.header &&[dataFrame.header.allKeys containsObject:@"heart-beat"]) {
        //设置心跳时间
        NSString *clientValues = self.clientHeartBeat;
        NSString *serverValues = dataFrame.header[@"heart-beat"];
        NSInteger cx, cy, sx, sy;
        
        NSScanner *scanner = [NSScanner scannerWithString:clientValues];
        scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@", "];
        [scanner scanInteger:&cx];
        [scanner scanInteger:&cy];
        
        scanner = [NSScanner scannerWithString:serverValues];
        scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@", "];
        [scanner scanInteger:&sx];
        [scanner scanInteger:&sy];
        
        NSInteger pingTTL = ceil(MAX(cx, sy) / 1000);
        NSInteger pongTTL = ceil(MAX(sx, cy) / 1000);
        if (self.isEnableClientPing && pingTTL > 0) {
            self.pingTimer = [NSTimer timerWithTimeInterval: pingTTL
                                                           target: self
                                                         selector: @selector(sendPing:)
                                                         userInfo: nil
                                                          repeats: YES];
            [[NSRunLoop currentRunLoop] addTimer:self.pingTimer forMode:NSRunLoopCommonModes];
            [self.pingTimer fire];
        }
        if (self.isEnableServerPong && pongTTL > 0) {
            self.pongTimer = [NSTimer timerWithTimeInterval: pongTTL
                                                           target: self
                                                         selector: @selector(checkPong:)
                                                         userInfo: @{@"ttl": [NSNumber numberWithInteger:pongTTL]}
                                                          repeats: YES];
            [[NSRunLoop currentRunLoop] addTimer:self.pongTimer forMode:NSRunLoopCommonModes];
            [self.pongTimer fire];
        }
    }
}

- (void)timerThreadSelector:(NSThread *)thread {
    [[NSRunLoop currentRunLoop] addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] run];
}

#pragma mark - Send Frame

- (void)sendFrameWithCommand:(NSString *)command
                     header:(NSDictionary *)header data:(NSString *)data {
    if (self.SRsocket.readyState == SR_OPEN) {
        STLog(@"send command name .......... %@", command);
        STLog(@"send header info .......... %@", header);
        KWSocketDataFrame *dataFrame = [[KWSocketDataFrame alloc] initWithCommand:command
                                                                           header:header
                                                                             data:data];
        [self.SRsocket send:dataFrame.socketSendData];
    }
}

- (void)sendPing:(NSTimer *)timer {
    if (!self.isConnect) {
        STLog(@"Ping ............. Socket not Connect Return");
        return;
    }
    [self.SRsocket send:[NSData data]];
    STLog(@"Ping ............. ");
}

- (void)checkPong:(NSTimer *)timer  {
    NSDictionary *dict = timer.userInfo;
    NSInteger ttl = [dict[@"ttl"] intValue];
    
    CFAbsoluteTime delta = CFAbsoluteTimeGetCurrent() - headerBeatTime;
    if (delta > (ttl * 3)) {
        STLog(@"did not receive server activity for the last %f seconds", delta);
        [self sendDisconnectWithHandler:self.disconnectHandlerBlock];
    }
}

#pragma mark - Decode Response

- (KWSocketDataFrame *)converStreamDataToFrameDataWithData:(NSData *)responseData {
    NSData *strData = [responseData subdataWithRange:NSMakeRange(0, [responseData length])];
    NSString *msg = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
    STLog(@"receive message ----- %@", msg);
    NSMutableArray *contents = (NSMutableArray *)[[msg componentsSeparatedByString:kFrameLineFeed] mutableCopy];
    while ([contents count] > 0 && [contents[0] isEqual:@""]) {
        [contents removeObjectAtIndex:0];
    }
    NSString *command = [[contents objectAtIndex:0] copy];
    NSMutableDictionary *header = [[NSMutableDictionary alloc] init];
    NSMutableString *data = [[NSMutableString alloc] init];
    BOOL hasHeaders = NO;
    [contents removeObjectAtIndex:0];
    for(NSString *line in contents) {
        if(hasHeaders) {
            for (int i=0; i < [line length]; i++) {
                unichar c = [line characterAtIndex:i];
                if (c != '\x00') {
                    [data appendString:[NSString stringWithFormat:@"%c", c]];
                }
            }
        } else {
            if ([line isEqual:@""]) {
                hasHeaders = YES;
            } else {
                NSMutableArray *parts = [NSMutableArray arrayWithArray:[line componentsSeparatedByString:kFrameHeaderSeparator]];
                NSString *key = parts[0];
                [parts removeObjectAtIndex:0];
                header[key] = [parts componentsJoinedByString:kFrameHeaderSeparator];
            }
        }
    }
    return [[KWSocketDataFrame alloc] initWithCommand:command header:header data:data];
}

- (void)didReceiveFrame:(KWSocketDataFrame *)dataFrame {
    if ([_commandKey(KWCommandTypeConnected) isEqualToString:dataFrame.command]) {
        //Connect Frame
        //心跳设置
        [self performSelector:@selector(configSocketWithConnectFrame:)
                     onThread:self.timerThread withObject:dataFrame waitUntilDone:NO];
//        [self configSocketWithConnectFrame:dataFrame];
        if (self.successHandlerBlock) {
            self.successHandlerBlock(dataFrame, nil);
        }
    } else if ([_commandKey(KWCommandTypeMessage) isEqualToString:dataFrame.command]) {
        //Message Frame
        NSString *identifier = [dataFrame.header valueForKey:@"subscription"];
        CompleteHandlerBlock handler = self.subscriptions[identifier];
        if (handler) {
            handler(dataFrame, nil);
        }
        
    } else if ([_commandKey(KWCommandTypeReceipt) isEqualToString:dataFrame.command]) {
        //Receipt Frame
    } else if ([_commandKey(KWCommandTypeError) isEqualToString:dataFrame.command]) {
        //Error Frame
        NSError *error = [[NSError alloc] initWithDomain:KWSocketErrorDomain code:KWSocketErrorDefault userInfo:@{@"frame": !dataFrame ? @"" : dataFrame }];
        // ERROR coming after the CONNECT frame
        if (!self.isConnect && self.successHandlerBlock) {
            self.successHandlerBlock(dataFrame, error);
        } else if(self.failureHandlerBlock) {
            if (self.failureHandlerBlock) {
                self.failureHandlerBlock(error);
            }
        } else {
            STLog(@"Unknow Error Frame: %@", dataFrame);
        }
    } else {
        NSError *error = [NSError errorWithDomain:KWSocketErrorDomain
                                             code:KWSocketErrorUnkwon
                                         userInfo:@{@"frame"   : !dataFrame ? @"" : dataFrame,
                                                    @"command" : !dataFrame.command ? @"" : dataFrame.command,
                                                    @"message" : @"didReceiveFrame error"
                                                    }];
        if (self.failureHandlerBlock) {
            self.failureHandlerBlock(error);
        }
    }
}

#pragma mark - SRWebSocketDelegate

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    STLog(@"Socket did Receive Message !!!!");
    self.isConnect = YES;
    headerBeatTime = CFAbsoluteTimeGetCurrent();
    KWSocketDataFrame *dataFrame = [self converStreamDataToFrameDataWithData:[message dataUsingEncoding:NSUTF8StringEncoding]];
    [self didReceiveFrame:dataFrame];
    [self.SRsocket send:[NSData data]];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    STLog(@"Socket did Open!!!!");
    self.isConnect = YES;
    headerBeatTime = CFAbsoluteTimeGetCurrent();
    [self sendConnectCommand];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload {
    STLog(@"Socket did Receive Pong!!!!");

}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    STLog(@"socket did Fail!!!");
    self.isConnect = NO;
    if (self.failureHandlerBlock) {
        self.failureHandlerBlock(error);
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(nullable NSString *)reason wasClean:(BOOL)wasClean {
    STLog(@"socket did close!!!");
    self.isConnect = NO;
    NSError *error = [NSError errorWithDomain:KWSocketErrorDomain code:code userInfo:@{ @"reason" : !reason ? @"" : reason }];
    if (self.disconnectHandlerBlock) {
        self.disconnectHandlerBlock(error);
    }
}

#pragma mark - Setter && Gerter

- (dispatch_queue_t)socketQueue {
    if (!_socketQueue) {
        self.socketQueue = dispatch_queue_create("Alex.SockectQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _socketQueue;
}

- (NSThread *)timerThread {
    if (!_timerThread) {
        self.timerThread = [[NSThread alloc] initWithTarget:self selector:@selector(timerThreadSelector:) object:nil];
        [_timerThread start];
    }
    return _timerThread;
}

- (NSMutableDictionary *)subscriptions {
    if (!_subscriptions) {
        self.subscriptions = @{}.mutableCopy;
    }
    return _subscriptions;
}

@end
