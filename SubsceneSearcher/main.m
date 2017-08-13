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
#import "NSString+Trim.h"

static void wizard()
{
    printf("Search subtitle: ");
    char *buffer = NULL;
    size_t bufferCapacity = 0;
    getline(&buffer, &bufferCapacity, stdin);
    NSString *searchTerm = [NSString stringWithUTF8String:buffer].stringByTrimmingWhitespaceAndNewline;
    printf("\n");

    NSArray<MovieEntry *> *movieEntries = searchMovies(searchTerm);
    if (movieEntries == nil) {
        fprintf(stderr, "ERROR: Movie lookup failed.\n");
        free(buffer);
        return;
    }
    if (movieEntries.count == 0) {
        printf("No results found.\n");
        free(buffer);
        return;
    }

    printf("Matches:\n");
    size_t index = 1;
    for (MovieEntry *entry in movieEntries) {
        printf("%zu: '%s' (%zu subtitles)\n", index++, entry.title.UTF8String, (size_t)entry.subtitleCount);
    }
    printf("\n");

    size_t movieIndex = 0;
    do {
        printf("Select movie: ");
        getline(&buffer, &bufferCapacity, stdin);
        movieIndex = (size_t)[NSString stringWithUTF8String:buffer].stringByTrimmingWhitespaceAndNewline.integerValue;
    } while (movieIndex < 1 || movieEntries.count < movieIndex);
    printf("\n");

    MovieEntry *movieEntry = movieEntries[movieIndex - 1];
    NSArray<SubtitleEntry *> *subtitleEntries = findSubtitlesForMovie(movieEntry);
    if (subtitleEntries == nil) {
        fprintf(stderr, "ERROR: Subtitle lookup failed.\n");
        free(buffer);
        return;
    }
    if (subtitleEntries.count == 0) {
        printf("There are no subtitles for the selected languages.\n");
        free(buffer);
        return;
    }

    printf("Subtitles:\n");
    index = 1;
    for (SubtitleEntry *entry in subtitleEntries) {
        printf("%zu: '%s' (%s) by %s\n", index++, entry.title.UTF8String, entry.language.UTF8String, entry.uploader.UTF8String);
    }
    printf("\n");

    size_t subtitleIndex = 0;
    do {
        printf("Select subtitle: ");
        getline(&buffer, &bufferCapacity, stdin);
        subtitleIndex = (size_t)[NSString stringWithUTF8String:buffer].stringByTrimmingWhitespaceAndNewline.integerValue;
    } while (subtitleIndex < 1 || subtitleEntries.count < subtitleIndex);
    printf("\n");

    SubtitleEntry *subtitleEntry = subtitleEntries[subtitleIndex - 1];
    NSData *subtitleArchive = downloadSubtitle(subtitleEntry);

    NSString *filePath = [NSString stringWithFormat:@"%@.zip", subtitleEntry.title];
    size_t duplicateIndex = 0;
    while ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        filePath = [NSString stringWithFormat:@"%@ (%zu).zip", subtitleEntry.title, ++duplicateIndex];
    }
    if (![subtitleArchive writeToFile:filePath atomically:YES]) {
        fprintf(stderr, "ERROR: Couldn't save '%s'.\n", filePath.UTF8String);
        free(buffer);
        return;
    }

    printf("Saved '%s'.\n", filePath.UTF8String);
    free(buffer);
}

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        wizard();
    }
    return 0;
}
