/*
 * Copyright 2017 Valentin Milea
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "HTTPUtil.h"

void HTTP_setCookie(NSHTTPCookieStorage *cookieStorage, NSString *domain, NSString *path, NSString *name, NSString *value)
{
    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{NSHTTPCookieDomain: domain,
                                                                NSHTTPCookiePath: path,
                                                                NSHTTPCookieName: name,
                                                                NSHTTPCookieValue: value
                                                                }];
    [cookieStorage setCookie:cookie];
}

NSData *HTTP_urlGet(NSURL *url, NSHTTPCookieStorage *cookieStorage)
{
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.HTTPCookieStorage = cookieStorage;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    __block NSData *urlData;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask *dataTask = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        urlData = data;
        dispatch_semaphore_signal(semaphore);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return urlData;
}
