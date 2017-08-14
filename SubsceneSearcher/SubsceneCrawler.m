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

#import "SubsceneCrawler.h"
#import "HTTPUtil.h"
#import "NSString+Trim.h"

#pragma mark - private

static NSString *const kSubsceneDomain = @"subscene.com";
static NSString *const kSubsceneHost = @"https://subscene.com";

static NSHTTPCookieStorage* subsceneCookieStorage()
{
    static NSHTTPCookieStorage *sCookieStorage = nil;
    if (sCookieStorage == nil) {
        sCookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:kSubsceneDomain];
        HTTP_setCookie(sCookieStorage, kSubsceneDomain, @"/", @"LanguageFilter", @"13,33"); // English, Romanian
        HTTP_setCookie(sCookieStorage, kSubsceneDomain, @"/", @"HearingImpaired", @"0");
        HTTP_setCookie(sCookieStorage, kSubsceneDomain, @"/", @"ForeignOnly", @"False");
        sCookieStorage.cookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    }
    return sCookieStorage;
}

static NSDictionary<NSString *, NSArray<MovieEntry *> *>* parseMovieEntries(HTMLDocument *document)
{
    HTMLElement *searchResultElement = [document firstNodeMatchingSelector:@"#content .search-result"];
    if (searchResultElement == nil) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSMutableArray<MovieEntry *> *> *searchResult = [NSMutableDictionary dictionary];
    NSString *category = @"Unclassified";
    for (HTMLElement *element in searchResultElement.childElementNodes) {
        if ([element.tagName hasPrefix:@"h"]) {
            category = element.textContent;
        } else if ([element.tagName isEqualToString:@"ul"]) {
            for (HTMLElement *listItemElement in element.childElementNodes) {
                MovieEntry *entry = [[MovieEntry alloc] init];

                HTMLElement *anchorElement = [listItemElement firstNodeMatchingSelector:@"a"];
                if (anchorElement != nil) {
                    entry.title = anchorElement.textContent;
                    NSString *href = anchorElement[@"href"];
                    if (href != nil) {
                        entry.url = [NSURL URLWithString:[kSubsceneHost stringByAppendingString:href]];
                    }
                }
                HTMLElement *countElement = [listItemElement firstNodeMatchingSelector:@".count"];
                if (countElement != nil) {
                    NSString *content = countElement.textContent;
                    NSArray<NSString *> *tokens =  [content componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    for (NSString *token in tokens) {
                        if (token.length > 0) {
                            NSInteger count = token.integerValue;
                            if (count > 0) {
                                entry.subtitleCount = count;
                                break;
                            }
                        }
                    }
                }
                if (entry.title != nil && entry.url != nil) {
                    NSMutableArray<MovieEntry *> *categoryEntries = searchResult[category];
                    if (categoryEntries == nil) {
                        categoryEntries = [NSMutableArray array];
                        searchResult[category] = categoryEntries;
                    }
                    [categoryEntries addObject:entry];
                }
            }
        }
    }
    return searchResult;
}

//static NSURL* parseIMDBLinkForSubtitles(HTMLDocument *document)
//{
//    HTMLElement *anchorElement = [document firstNodeMatchingSelector:@".subtitles .header a"];
//    NSString *href = anchorElement[@"href"];
//    if (href == nil) {
//        return nil;
//    } else {
//        NSURL *url = [NSURL URLWithString:href];
//        return url;
//    }
//}

static NSArray<SubtitleEntry *>* parseSubtitleEntries(HTMLDocument *document)
{
    HTMLElement *tableElement = [document firstNodeMatchingSelector:@".content tbody"];
    if (tableElement == nil) {
        return nil;
    }

    NSMutableArray<SubtitleEntry *> *subtitleEntries = [NSMutableArray array];
    for (HTMLElement *rowElement in tableElement.childElementNodes) {
        SubtitleEntry *entry = [[SubtitleEntry alloc] init];

        NSArray<HTMLElement *> *anchorElements = [rowElement nodesMatchingSelector:@"a"];
        if (anchorElements.count > 0) {
            HTMLElement *anchorElement = anchorElements[0];
            NSString *href = anchorElement[@"href"];
            if (href != nil) {
                if ([href hasPrefix:@"http"]) {
                    //looks like an upload link, no subtitles found
                    if (subtitleEntries.count == 0) {
                        break;
                    }
                } else {
                    entry.url = [NSURL URLWithString:[kSubsceneHost stringByAppendingString:href]];
                }
            }
            NSArray<HTMLElement *> *subElements = [anchorElement nodesMatchingSelector:@"span"];
            if (subElements.count > 0) {
                entry.language = [subElements[0].textContent stringByTrimmingWhitespaceAndNewline];
            }
            if (subElements.count > 1) {
                entry.title = [subElements[1].textContent stringByTrimmingWhitespaceAndNewline];
            }
        }
        if (anchorElements.count > 1) {
            HTMLElement *anchorElement = anchorElements[1];
            entry.uploader = [anchorElement.textContent stringByTrimmingWhitespaceAndNewline];
        }
        HTMLElement *commentElement = [rowElement firstNodeMatchingSelector:@"div"];
        if (commentElement != nil) {
            entry.comment = [commentElement.textContent stringByTrimmingWhitespaceAndNewline];
        }

        if (entry.url != nil) {
            [subtitleEntries addObject:entry];
        }
    }
    return subtitleEntries;
}

static NSURL* parseSubtitleLink(HTMLDocument *document)
{
    HTMLElement *anchorElement = [document firstNodeMatchingSelector:@"#downloadButton"];
    NSString *href = anchorElement[@"href"];
    if (href == nil) {
        return nil;
    } else {
        NSURL *url = [NSURL URLWithString:[kSubsceneHost stringByAppendingString:href]];
        return url;
    }
}

#pragma mark - public

NSDictionary<NSString *, NSArray<MovieEntry *> *>* searchMovies(NSString *term)
{
    NSArray<NSString *> *tokens = [term componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableString *query = [NSMutableString stringWithFormat:@"%@/subtitles/title?q=", kSubsceneHost];
    for (NSString *token in tokens) {
        NSString *escapedToken = token.html_stringByEscapingForHTML;
        if (query.length > 0) {
            [query appendString:@"+"];
        }
        [query appendString:escapedToken];
    }

    NSURL *url = [NSURL URLWithString:query];
    NSData *data = HTTP_urlGet(url, subsceneCookieStorage());
    HTMLDocument *document = [HTMLDocument documentWithData:data contentTypeHeader:nil];

    NSDictionary<NSString *, NSArray<MovieEntry *> *> *searchResult = parseMovieEntries(document);
    return searchResult;
}

NSArray<SubtitleEntry *>* findSubtitlesForMovie(MovieEntry *movieEntry)
{
    NSData *data = HTTP_urlGet(movieEntry.url, subsceneCookieStorage());
    if (data == nil) {
        return nil;
    }
    HTMLDocument *document = [HTMLDocument documentWithData:data contentTypeHeader:nil];
    NSArray<SubtitleEntry *> *subtitleEntries = parseSubtitleEntries(document);
    return subtitleEntries;
}

NSData* downloadSubtitle(SubtitleEntry *subtitleEntry)
{
    NSData *data = HTTP_urlGet(subtitleEntry.url, subsceneCookieStorage());
    if (data == nil) {
        return nil;
    }
    HTMLDocument *document = [HTMLDocument documentWithData:data contentTypeHeader:nil];
    NSURL *subtitleURL = parseSubtitleLink(document);
    if (subtitleURL == nil) {
        return nil;
    }
    data = HTTP_urlGet(subtitleURL, subsceneCookieStorage());
    return data;
}
