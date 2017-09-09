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

#import <Foundation/Foundation.h>
#import "SubsceneModel.h"

#pragma mark - misc

typedef NS_ENUM(NSUInteger, SubsceneQueryResultKind)
{
    SubsceneQueryResultProductions,  // NSDictionary<NSString *, NSArray<ProductionEntry *> *>
    SubsceneQueryResultSubtitles     // NSArray<SubtitleEntry *>
};

@interface SubsceneQueryResult : NSObject

@property (nonatomic) SubsceneQueryResultKind kind;
@property (nonatomic) id items;

@end

#pragma mark - scraper API

SubsceneQueryResult* querySubscene(NSString *term);

NSArray<SubtitleEntry *>* querySubtitlesForProduction(ProductionEntry *productionEntry);

NSData* downloadSubtitle(SubtitleEntry *subtitleEntry);
