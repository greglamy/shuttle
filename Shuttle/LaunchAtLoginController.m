//
//  LaunchAtLoginController.m
//
//  Copyright 2011 Tomáš Znamenáček
//  Copyright 2010 Ben Clark-Robinson
//
//  Permission is hereby granted, free of charge, to any person obtaining
//  a copy of this software and associated documentation files (the ‘Software’),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "LaunchAtLoginController.h"
#import <ServiceManagement/ServiceManagement.h>

//This class used to drive the login items through LSSharedFileList, which has been
//deprecated since macOS 10.11 and is a no-op on current systems. SMAppService is the
//supported replacement: it registers this very app bundle as a login item, and the
//item shows up in System Settings > General > Login Items.

static NSString *const StartAtLoginKey = @"launchAtLogin";

@implementation LaunchAtLoginController

#pragma mark Launch List Control

- (BOOL) isMainBundleURL: (NSURL*) itemURL
{
    //SMAppService only knows about this app bundle, never about an arbitrary URL.
    return itemURL != nil
        && [[itemURL URLByStandardizingPath] isEqual:[[self appURL] URLByStandardizingPath]];
}

- (BOOL) willLaunchAtLogin: (NSURL*) itemURL
{
    if (![self isMainBundleURL:itemURL])
        return NO;
    
    return [[SMAppService mainAppService] status] == SMAppServiceStatusEnabled;
}

- (void) setLaunchAtLogin: (BOOL) enabled forURL: (NSURL*) itemURL
{
    if (![self isMainBundleURL:itemURL])
        return;
    
    SMAppService *mainApp = [SMAppService mainAppService];
    SMAppServiceStatus status = [mainApp status];
    NSError *error = nil;
    
    if (enabled) {
        //Registered already, or registered and waiting for the user to allow it.
        if (status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval)
            return;
        if (![mainApp registerAndReturnError:&error])
            NSLog(@"shuttle: unable to enable launch at login: %@", error);
    } else {
        //Nothing registered, nothing to remove.
        if (status == SMAppServiceStatusNotRegistered || status == SMAppServiceStatusNotFound)
            return;
        if (![mainApp unregisterAndReturnError:&error])
            NSLog(@"shuttle: unable to disable launch at login: %@", error);
    }
}

#pragma mark Basic Interface

- (NSURL*) appURL
{
    return [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
}

- (void) setLaunchAtLogin: (BOOL) enabled
{
    [self willChangeValueForKey:StartAtLoginKey];
    [self setLaunchAtLogin:enabled forURL:[self appURL]];
    [self didChangeValueForKey:StartAtLoginKey];
}

- (BOOL) launchAtLogin
{
    return [self willLaunchAtLogin:[self appURL]];
}

@end
