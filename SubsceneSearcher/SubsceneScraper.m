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

#import "SubsceneScraper.h"
#import "HTTPUtil.h"
#import "NSString+Trim.h"

@implementation SubsceneQueryResult

@end

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

static NSDictionary<NSString *, NSArray<ProductionEntry *> *>* parseCategorizedSearchResult(HTMLElement *searchResultElement)
{
    NSMutableDictionary<NSString *, NSMutableArray<ProductionEntry *> *> *searchResult = [NSMutableDictionary dictionary];
    NSString *category = @"Unclassified";
    for (HTMLElement *element in searchResultElement.childElementNodes) {
        if ([element.tagName hasPrefix:@"h"]) {
            category = element.textContent;
        } else if ([element.tagName isEqualToString:@"ul"]) {
            for (HTMLElement *listItemElement in element.childElementNodes) {
                ProductionEntry *entry = [[ProductionEntry alloc] init];

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
                    NSMutableArray<ProductionEntry *> *categoryEntries = searchResult[category];
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

static SubtitleEntry* parseSubtitleEntry(HTMLElement *tableRowElement)
{
    SubtitleEntry *entry = [[SubtitleEntry alloc] init];
    NSArray<HTMLElement *> *anchorElements = [tableRowElement nodesMatchingSelector:@"a"];
    if (anchorElements.count > 0) {
        HTMLElement *anchorElement = anchorElements[0];
        NSString *href = anchorElement[@"href"];
        if (href != nil) {
            if ([href hasPrefix:@"http"]) {
                //looks like an upload link, skip
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
    HTMLElement *commentElement = [tableRowElement firstNodeMatchingSelector:@"div"];
    if (commentElement != nil) {
        entry.comment = [commentElement.textContent stringByTrimmingWhitespaceAndNewline];
    }
    return (entry.url != nil ? entry : nil);
}

static NSArray<SubtitleEntry *>* parseSubtitleTable(HTMLElement *tableElement)
{
    HTMLElement *tableBodyElement = [tableElement firstNodeMatchingSelector:@"tbody"];
    if (tableBodyElement == nil) {
        return nil;
    }
    NSMutableArray<SubtitleEntry *> *subtitleEntries = [NSMutableArray array];
    for (HTMLElement *tableRowElement in tableBodyElement.childElementNodes) {
        SubtitleEntry *entry = parseSubtitleEntry(tableRowElement);
        if (entry == nil) {
            if (subtitleEntries.count == 0) {
                return nil; //assume invalid table format if the first entry is unparsable
            }
        } else {
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

SubsceneQueryResult* querySubscene(NSString *term)
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
    HTMLElement *contentElement = [document firstNodeMatchingSelector:@"#content"];
    if (contentElement == nil) {
        return nil;
    }
    HTMLElement *searchResultElement = [contentElement firstNodeMatchingSelector:@".search-result"];
    if (searchResultElement != nil) {
        SubsceneQueryResult *result = [[SubsceneQueryResult alloc] init];
        result.items = parseCategorizedSearchResult(searchResultElement);
        result.kind = SubsceneQueryResultProductions;
        return result;
    }
    HTMLElement *subtitleTableElement = [contentElement firstNodeMatchingSelector:@".content table"];
    if (subtitleTableElement != nil) {
        SubsceneQueryResult *result = [[SubsceneQueryResult alloc] init];
        result.items = parseSubtitleTable(subtitleTableElement);
        result.kind = SubsceneQueryResultSubtitles;
        return result;
    }
    return nil;
}

NSArray<SubtitleEntry *>* querySubtitlesForProduction(ProductionEntry *productionEntry)
{
    NSData *data = HTTP_urlGet(productionEntry.url, subsceneCookieStorage());
    if (data == nil) {
        return nil;
    }
    HTMLDocument *document = [HTMLDocument documentWithData:data contentTypeHeader:nil];
    HTMLElement *subtitleTableElement = [document firstNodeMatchingSelector:@".content table"];
    if (subtitleTableElement == nil) {
        return nil;
    }
    NSArray<SubtitleEntry *> *subtitleEntries = parseSubtitleTable(subtitleTableElement);
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
