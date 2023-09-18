// ignore_for_file: constant_identifier_names

// exporting playback enums
export 'package:basic_audio_handler/basic_audio_handler.dart' show RepeatMode, InterruptionType, InterruptionAction;

enum SortType {
  title,
  album,
  albumArtist,
  year,
  artistsList,
  genresList,
  dateAdded,
  dateModified,
  bitrate,
  composer,
  discNo,
  filename,
  duration,
  sampleRate,
  size,
  rating,
  shuffle,
}

enum GroupSortType {
  title,
  album,
  albumArtist,
  year,
  artistsList,
  genresList,
  dateModified,
  composer,
  duration,
  numberOfTracks,
  albumsCount,
  creationDate,
  modifiedDate,
  shuffle,
}

enum TrackTilePosition {
  row1Item1,
  row1Item2,
  row1Item3,
  row2Item1,
  row2Item2,
  row2Item3,
  row3Item1,
  row3Item2,
  row3Item3,
  rightItem1,
  rightItem2,
  rightItem3,
}

enum TrackTileItem {
  none,
  title,
  album,
  artists,
  albumArtist,
  genres,
  composer,
  trackNumber,
  discNumber,
  duration,
  year,
  size,
  dateAdded,
  dateModified,
  dateModifiedDate,
  dateModifiedClock,
  path,
  folder,
  fileName,
  fileNameWOExt,
  extension,
  comment,
  bitrate,
  sampleRate,
  format,
  channels,
  rating,
  tags,
  moods,
}

enum TrackSearchFilter {
  title,
  album,
  artist,
  albumartist,
  genre,
  composer,
  year,
}

enum LibraryTab {
  home,
  albums,
  tracks,
  artists,
  genres,
  playlists,
  folders,
  search,
}

enum TrackPlayMode {
  selectedTrack,
  searchResults,
  trackAlbum,
  trackArtist,
  trackGenre,
}

enum TrackSource {
  local,
  youtube,
  youtubeMusic,
  lastfm,
}

enum QueueSource {
  allTracks,
  album,
  artist,
  genre,
  playlist,
  folder,
  search,
  queuePage,
  playerQueue,
  mostPlayed,
  history,
  favourites,
  selectedTracks,
  externalFile,
  homePageItem,
  others,
}

enum TagField {
  title,
  artist,
  album,
  albumArtist,
  composer,
  genre,
  year,
  trackNumber,
  discNumber,
  comment,
  lyrics,
  remixer,
  trackTotal,
  discTotal,
  lyricist,
  language,
  recordLabel,
  country,
}

enum FFMPEGTagField {
  title,
  artist,
  album,
  albumArtist,
  composer,
  synopsis,
  description,
  genre,
  year,
  trackNumber,
  discNumber,
  comment,
  lyrics,
  remixer,
  lyricist,
  language,
  recordLabel,
  country,
}

enum WakelockMode {
  none,
  expanded,
  expandedAndVideo,
}

enum RouteType {
  // ----- Pages -----
  PAGE_HOME,
  PAGE_allTracks,
  PAGE_albums,
  PAGE_artists,
  PAGE_genres,
  PAGE_playlists,
  PAGE_folders,
  PAGE_queue,
  PAGE_stats,

  // ----- Subpages -----
  SUBPAGE_recentlyAddedTracks,
  SUBPAGE_albumTracks,
  SUBPAGE_artistTracks,
  SUBPAGE_genreTracks,
  SUBPAGE_playlistTracks,
  SUBPAGE_historyTracks,
  SUBPAGE_mostPlayedTracks,
  SUBPAGE_queueTracks,

  // ----- Subpages -----
  SETTINGS_page,
  SETTINGS_subpage,

  // ----- Search Results -----
  SEARCH_albumResults,
  SEARCH_artistResults,

  // ----- Youtube -----
  YOUTUBE_HOME,

  /// others
  UNKNOWN,
}

/// Used for search and sort.
enum MediaType {
  track,
  album,
  artist,
  genre,
  playlist,

  /// not used
  folder,
}

enum VideoPlaybackSource {
  auto,
  local,
  youtube,
}

enum QueueInsertionType {
  moreAlbum,
  moreArtist,
  moreFolder,
  random,
  listenTimeRange,
  mood,
  rating,
  sameReleaseDate,
  algorithm,
}

enum InsertionSortingType {
  random,
  listenCount,
  rating,
}

enum MostPlayedTimeRange {
  custom,
  day,
  day3,
  week,
  month,
  month3,
  month6,
  year,
  allTime,
}

enum LocalVideoMatchingType {
  auto,
  filename,
  titleAndArtist,
}

enum HomePageItems {
  mixes,
  recentListens,
  topRecentListens,
  lostMemories,
  recentlyAdded,
  recentAlbums,
  recentArtists,
  topRecentAlbums,
  topRecentArtists,
}

enum MixesItems {
  topRecents,
  supremacy,
  favourites,
  randomPicks,
}

enum NotificationTapAction {
  openApp,
  openMiniplayer,
  openQueue,
}
