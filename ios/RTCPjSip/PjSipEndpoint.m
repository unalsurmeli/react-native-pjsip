@import AVFoundation;

#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTUtils.h>

#import "PjSipEndpoint.h"
#import "pjsua.h"

@implementation PjSipEndpoint

+ (instancetype) instance {
    static PjSipEndpoint *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PjSipEndpoint alloc] init];
    });

    return sharedInstance;
}

- (instancetype) init {
    self = [super init];
    self.accounts = [[NSMutableDictionary alloc] initWithCapacity:12];
    self.calls = [[NSMutableDictionary alloc] initWithCapacity:12];

    pj_status_t status;

    // Create pjsua first
    status = pjsua_create();
    if (status != PJ_SUCCESS) {
        NSLog(@"Error in pjsua_create()");
    }

    // Init pjsua
    {
        // Init the config structure
        pjsua_config cfg;
        pjsua_config_default(&cfg);

        // cfg.cb.on_reg_state = [self performSelector:@selector(onRegState:) withObject: o];
        cfg.cb.on_reg_state = &onRegStateChanged;
        cfg.cb.on_incoming_call = &onCallReceived;
        cfg.cb.on_call_state = &onCallStateChanged;
        cfg.cb.on_call_media_state = &onCallMediaStateChanged;
        
//        cfg.cfg.cb.on_call_media_state = &on_call_media_state;
//        cfg.cfg.cb.on_incoming_call = &on_incoming_call;
//        cfg.cfg.cb.on_call_tsx_state = &on_call_tsx_state;
//        cfg.cfg.cb.on_dtmf_digit = &call_on_dtmf_callback;
//        cfg.cfg.cb.on_call_redirected = &call_on_redirected;
//        cfg.cfg.cb.on_reg_state = &on_reg_state;
//        cfg.cfg.cb.on_incoming_subscribe = &on_incoming_subscribe;
//        cfg.cfg.cb.on_buddy_state = &on_buddy_state;
//        cfg.cfg.cb.on_buddy_evsub_state = &on_buddy_evsub_state;
//        cfg.cfg.cb.on_pager = &on_pager;
//        cfg.cfg.cb.on_typing = &on_typing;
//        cfg.cfg.cb.on_call_transfer_status = &on_call_transfer_status;
//        cfg.cfg.cb.on_call_replaced = &on_call_replaced;
//        cfg.cfg.cb.on_nat_detect = &on_nat_detect;
//        cfg.cfg.cb.on_mwi_info = &on_mwi_info;
//        cfg.cfg.cb.on_transport_state = &on_transport_state;
//        cfg.cfg.cb.on_ice_transport_error = &on_ice_transport_error;
//        cfg.cfg.cb.on_snd_dev_operation = &on_snd_dev_operation;
//        cfg.cfg.cb.on_call_media_event = &on_call_media_event;

        // Init the logging config structure
        pjsua_logging_config log_cfg;
        pjsua_logging_config_default(&log_cfg);
        log_cfg.console_level = 10;

        // Init media config
        pjsua_media_config mediaConfig;
        pjsua_media_config_default(&mediaConfig);
        mediaConfig.clock_rate = PJSUA_DEFAULT_CLOCK_RATE;
        mediaConfig.snd_clock_rate = 0;
        
        // Init the pjsua
        status = pjsua_init(&cfg, &log_cfg, &mediaConfig);
        if (status != PJ_SUCCESS) {
            NSLog(@"Error in pjsua_init()");
        }
    }

    // Add UDP transport.
    {
        // Init transport config structure
        pjsua_transport_config cfg;
        pjsua_transport_config_default(&cfg);

        // Add TCP transport.
        status = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &cfg, NULL);
        if (status != PJ_SUCCESS) NSLog(@"Error creating transport");
    }

    // Add TCP transport.
    {
        // Init transport config structure
        pjsua_transport_config cfg;
        pjsua_transport_config_default(&cfg);

        // Add TCP transport.
        status = pjsua_transport_create(PJSIP_TRANSPORT_TCP, &cfg, NULL);
        if (status != PJ_SUCCESS) NSLog(@"Error creating transport");
    }

    // Initialization is done, now start pjsua
    status = pjsua_start();
    if (status != PJ_SUCCESS) NSLog(@"Error starting pjsua");

    return self;
}

- (NSDictionary *) start {
    NSMutableArray *accountsResult = [[NSMutableArray alloc] initWithCapacity:[@([self.accounts count]) unsignedIntegerValue]];
    NSMutableArray *callsResult = [[NSMutableArray alloc] initWithCapacity:[@([self.calls count]) unsignedIntegerValue]];

    for (NSString *key in self.accounts) {
        PjSipAccount *acc = self.accounts[key];
        [accountsResult addObject:[acc toJsonDictionary]];
    }
    
    for (NSString *key in self.calls) {
        PjSipCall *call = self.calls[key];
        [callsResult addObject:[call toJsonDictionary:self.isSpeaker]];
    }
    
    return @{@"accounts": accountsResult, @"calls": callsResult, @"connectivity": @YES};
}

- (PjSipAccount *)createAccount:(NSDictionary *)config {
    PjSipAccount *account = [PjSipAccount itemConfig:config];
    self.accounts[@(account.id)] = account;

    return account;
}

- (void)deleteAccount:(int) accountId {
    // TODO: Destroy function ?
    if (self.accounts[@(accountId)] == nil) {
        [NSException raise:@"Failed to delete account" format:@"Account with %@ id not found", @(accountId)];
    }

    [self.accounts removeObjectForKey:@(accountId)];
}

- (PjSipAccount *) findAccount: (int) accountId {
    return self.accounts[@(accountId)];
}


#pragma mark Calls

-(PjSipCall *)makeCall:(PjSipAccount *) account destination:(NSString *)destination {
    pjsua_call_id callId;
    pj_str_t callDest = pj_str((char *) [destination UTF8String]);
    pjsua_msg_data callMsg;
    pjsua_msg_data_init(&callMsg);

    pj_status_t status = pjsua_call_make_call(account.id, &callDest, NULL, NULL, &callMsg, &callId);
    if (status != PJ_SUCCESS) {
        [NSException raise:@"Failed to make a call" format:@"See device logs for more details."];
    }
    
    PjSipCall *call = [PjSipCall itemConfig:callId];
    self.calls[@(callId)] = call;
    
    return call;
}

- (PjSipCall *) findCall: (int) callId {
    return self.calls[@(callId)];
}

-(void)useSpeaker {
    self.isSpeaker = true;
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    
    for (NSString *key in self.calls) {
        PjSipCall *call = self.calls[key];
        [self emmitCallChanged:call];
    }
}

-(void)useEarpiece {
    self.isSpeaker = false;
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:nil];
    
    for (NSString *key in self.calls) {
        PjSipCall *call = self.calls[key];
        [self emmitCallChanged:call];
    }
}

#pragma mark - Events

-(void)emmitRegistrationChanged:(PjSipAccount*) account {
    [self emmitEvent:@"pjSipRegistrationChanged" body:[account toJsonDictionary]];
}

-(void)emmitCallReceived:(PjSipCall*) call {
    [self emmitEvent:@"pjSipCallReceived" body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitCallChanged:(PjSipCall*) call {
    [self emmitEvent:@"pjSipCallChanged" body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitCallTerminated:(PjSipCall*) call {
    [self emmitEvent:@"pjSipCallTerminated" body:[call toJsonDictionary:self.isSpeaker]];
}

-(void)emmitEvent:(NSString*) name body:(id)body {
    [[self.bridge eventDispatcher] sendAppEventWithName:name body:body];
}

#pragma mark - Callbacks

static void onRegStateChanged(pjsua_acc_id accId) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    PjSipAccount* account = [endpoint findAccount:accId];
    
    if (account) {
        [endpoint emmitRegistrationChanged:account];
    }
}

static void onCallReceived(pjsua_acc_id accId, pjsua_call_id callId, pjsip_rx_data *rx) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    
    PjSipCall *call = [PjSipCall itemConfig:callId];
    endpoint.calls[@(callId)] = call;
    
    [endpoint emmitCallReceived:call];
}

static void onCallStateChanged(pjsua_call_id callId, pjsip_event *event) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    
    pjsua_call_info callInfo;
    pjsua_call_get_info(callId, &callInfo);
    
    PjSipCall* call = [endpoint findCall:callId];
    
    if (!call) {
        return;
    }
    
    [call onStateChanged:callInfo];
    
    if (callInfo.state == PJSIP_INV_STATE_DISCONNECTED) {
        [endpoint.calls removeObjectForKey:@(callId)];
        [endpoint emmitCallTerminated:call];
    } else {
        [endpoint emmitCallChanged:call];
    }
}

static void onCallMediaStateChanged(pjsua_call_id callId) {
    PjSipEndpoint* endpoint = [PjSipEndpoint instance];
    
    pjsua_call_info callInfo;
    pjsua_call_get_info(callId, &callInfo);
    
    PjSipCall* call = [endpoint findCall:callId];
    
    if (call) {
        [call onMediaStateChanged:callInfo];
    }
    
    [endpoint emmitCallChanged:call];
}


@end
