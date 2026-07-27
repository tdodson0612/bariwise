#!/usr/bin/env python3
import re
import os

# Map old constant names to new lowerCamelCase names
RENAMES = {
    'ALBUM_BUCKET': 'albumBucket',
    'BACKGROUND_BUCKET': 'backgroundBucket',
    'BPD_DS': 'bpdDs',
    'CACHE_BADGES': 'cacheBadges',
    'CACHE_FAVORITE_RECIPES': 'cacheFavoriteRecipes',
    'CACHE_FRIENDS': 'cacheFriends',
    'CACHE_LAST_MESSAGE_TIME': 'cacheLastMessageTime',
    'CACHE_LAST_POST_TIME': 'cacheLastPostTime',
    'CACHE_MESSAGES': 'cacheMessages',
    'CACHE_POSTS': 'cachePosts',
    'CACHE_PROFILE_TIMESTAMP': 'cacheProfileTimestamp',
    'CACHE_SUBMITTED_RECIPES': 'cacheSubmittedRecipes',
    'CACHE_USER_BADGES': 'cacheUserBadges',
    'CACHE_USER_POSTS': 'cacheUserPosts',
    'CACHE_USER_PROFILE': 'cacheUserProfile',
    'FREE_DAILY_SCANS': 'freeDailyScans',
    'GASTRIC_BAND': 'gastricBand',
    'GASTRIC_BYPASS': 'gastricBypass',
    'KNOWN_BUCKETS': 'knownBuckets',
    'LAST_SCAN_DATE_KEY': 'lastScanDateKey',
    'MINI_BYPASS': 'miniBypass',
    'NOT_SPECIFIED': 'notSpecified',
    'OTHER': 'other',
    'PROFILE_BUCKET': 'profileBucket',
    'SCAN_COUNT_KEY': 'scanCountKey',
    'SLEEVE': 'sleeve',
    'TUTORIAL_ALL_BUTTONS': 'tutorialAllButtons',
    'TUTORIAL_CLOSE': 'tutorialClose',
    'TUTORIAL_INTRO': 'tutorialIntro',
    'TUTORIAL_LOOKUP': 'tutorialLookup',
    'TUTORIAL_MANUAL': 'tutorialManual',
    'TUTORIAL_SCAN': 'tutorialScan',
    'TUTORIAL_UNIFIED_RESULT': 'tutorialUnifiedResult',
    '_ALBUM_BUCKET': '_albumBucket',
    '_BACKGROUND_BUCKET': '_backgroundBucket',
    '_CACHE_BADGES': '_cacheBadges',
    '_CACHE_DURATION': '_cacheDuration',
    '_CACHE_FAVORITE_RECIPES': '_cacheFavoriteRecipes',
    '_CACHE_FRIENDS': '_cacheFriends',
    '_CACHE_KEY': '_cacheKey',
    '_CACHE_LAST_MESSAGE_TIME': '_cacheLastMessageTime',
    '_CACHE_LAST_POST_TIME': '_cacheLastPostTime',
    '_CACHE_MESSAGES': '_cacheMessages',
    '_CACHE_POSTS': '_cachePosts',
    '_CACHE_PROFILE_TIMESTAMP': '_cacheProfileTimestamp',
    '_CACHE_SUBMITTED_RECIPES': '_cacheSubmittedRecipes',
    '_CACHE_USER_BADGES': '_cacheUserBadges',
    '_CACHE_USER_POSTS': '_cacheUserPosts',
    '_CACHE_USER_PROFILE': '_cacheUserProfile',
    '_DAY7_POPUP_KEY': '_day7PopupKey',
    '_DISCLAIMER_KEY': '_disclaimerKey',
    '_KNOWN_BUCKETS': '_knownBuckets',
    '_OPERATION_COOLDOWN': '_operationCooldown',
    '_PREF_EXERCISE_UNIT': '_prefExerciseUnit',
    '_PREF_WATER_UNIT': '_prefWaterUnit',
    '_PREF_WEIGHT_UNIT': '_prefWeightUnit',
    '_PROFILE_BUCKET': '_profileBucket',
    '_STORAGE_KEY_PREFIX': '_storageKeyPrefix',
}

# Build regex patterns with word boundaries
PATTERNS = {}
for old, new in RENAMES.items():
    PATTERNS[old] = (re.compile(r'\b' + re.escape(old) + r'\b'), new)

updated_files = []

for root, dirs, files in os.walk('lib'):
    for fname in files:
        if not fname.endswith('.dart'):
            continue
        filepath = os.path.join(root, fname)
        with open(filepath, 'r') as f:
            content = f.read()
        
        original = content
        for old, (pattern, new) in PATTERNS.items():
            content = pattern.sub(new, content)
        
        if content != original:
            with open(filepath, 'w') as f:
                f.write(content)
            updated_files.append(filepath)

for f in updated_files:
    print(f'Updated: {f}')

print(f'Updated {len(updated_files)} files')
