#import "AppGroupDirectoryPlugin.h"

@implementation AppGroupDirectoryPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"me.wolszon.app_group_directory/channel"
            binaryMessenger:[registrar messenger]];
  AppGroupDirectoryPlugin* instance = [[AppGroupDirectoryPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getAppGroupDirectory" isEqualToString:call.method]) {
    result([self getAppGroupDirectoryWithId:call.arguments]);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (NSString*)getAppGroupDirectoryWithId:(NSString*)groupId {
  NSFileManager* fileManager = [NSFileManager defaultManager];
  NSURL *groupURL = [fileManager containerURLForSecurityApplicationGroupIdentifier:groupId];
  return [groupURL path];
}

@end
