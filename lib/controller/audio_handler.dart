import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:basic_audio_handler/basic_audio_handler.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:get/get_utils/src/extensions/num_extensions.dart';
import 'package:just_audio/just_audio.dart';
import 'package:newpipeextractor_dart/newpipeextractor_dart.dart';

import 'package:namida/class/track.dart';
import 'package:namida/class/youtube_id.dart';
import 'package:namida/controller/current_color.dart';
import 'package:namida/controller/history_controller.dart';
import 'package:namida/controller/indexer_controller.dart';
import 'package:namida/controller/lyrics_controller.dart';
import 'package:namida/controller/player_controller.dart';
import 'package:namida/controller/playlist_controller.dart';
import 'package:namida/controller/queue_controller.dart';
import 'package:namida/controller/settings_controller.dart';
import 'package:namida/controller/video_controller.dart';
import 'package:namida/controller/waveform_controller.dart';
import 'package:namida/controller/youtube_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/namida_converter_ext.dart';
import 'package:namida/ui/dialogs/common_dialogs.dart';

class NamidaAudioVideoHandler<Q extends Playable> extends BasicAudioHandler<Q> {
  Selectable get currentTrack => (currentItem is Selectable ? currentItem as Selectable : null) ?? kDummyTrack;
  YoutubeID? get currentVideo => currentItem is YoutubeID ? currentItem as YoutubeID : null;
  List<Selectable> get currentQueueSelectable => currentQueue.firstOrNull is Selectable ? currentQueue.cast<Selectable>() : [];
  List<YoutubeID> get currentQueueYoutubeID => currentQueue.firstOrNull is YoutubeID ? currentQueue.cast<YoutubeID>() : [];

  final currentVideoInfo = Rxn<VideoInfo>();
  final currentVideoStream = Rxn<VideoOnlyStream>();
  final currentVideoThumbnail = Rxn<File>();

  /// Milliseconds should be awaited before playing video.
  int get _videoPositionSeekDelayMS => 500;

  Future<void> _waitForAllBuffers() async {
    await Future.wait([
      if (waitTillAudioLoaded != null) waitTillAudioLoaded!,
      if (VideoController.vcontroller.waitTillBufferingComplete != null) VideoController.vcontroller.waitTillBufferingComplete!,
      if (bufferingCompleter != null) bufferingCompleter!.future,
    ]);
  }

  Future<void> prepareTotalListenTime() async {
    final file = await File(AppPaths.TOTAL_LISTEN_TIME).create();
    final text = await file.readAsString();
    final listenTime = int.tryParse(text);
    super.initializeTotalListenTime(listenTime);
  }

  Future<void> _updateTrackLastPosition(Track track, int lastPositionMS) async {
    /// Saves a starting position in case the remaining was less than 30 seconds.
    final remaining = (track.duration * 1000) - lastPositionMS;
    final positionToSave = remaining <= 30000 ? 0 : lastPositionMS;

    await Indexer.inst.updateTrackStats(track, lastPositionInMs: positionToSave);
  }

  Future<void> tryRestoringLastPosition(Track trackPre) async {
    final minValueInSet = settings.minTrackDurationToRestoreLastPosInMinutes.value * 60;

    if (minValueInSet > 0) {
      final seekValueInMS = settings.seekDurationInSeconds.value * 1000;
      final track = trackPre.toTrackExt();
      final lastPos = track.stats.lastPositionInMs;
      // -- only seek if not at the start of track.
      if (lastPos >= seekValueInMS && track.duration >= minValueInSet) {
        await seek(lastPos.milliseconds);
      }
    }
  }

  //
  // =================================================================================
  // ================================ Video Methods ==================================
  // =================================================================================

  Future<void> refreshVideoPosition() async {
    await VideoController.vcontroller.seek(Duration(milliseconds: currentPositionMS));
  }

  Future<void> _playAudioThenVideo() async {
    onPlayRaw();
    await Future.delayed(Duration(milliseconds: _videoPositionSeekDelayMS.abs()));
    await VideoController.vcontroller.play();
  }
  // =================================================================================
  //

  //
  // =================================================================================
  // ================================ Player methods =================================
  // =================================================================================

  void refreshNotification([Q? item, VideoInfo? videoInfo]) {
    item ?? currentItem;
    item?._execute(
      selectable: (finalItem) async {
        _notificationUpdateItem(item: item, isItemFavourite: finalItem.track.isFavourite, itemIndex: currentIndex);
      },
      youtubeID: (finalItem) async {
        _notificationUpdateItem(item: item, isItemFavourite: false, itemIndex: currentIndex, videoInfo: videoInfo);
      },
    );
  }

  void _notificationUpdateItem({required Q item, required bool isItemFavourite, required int itemIndex, VideoInfo? videoInfo}) {
    item._execute(
      selectable: (finalItem) async {
        mediaItem.add(finalItem.toMediaItem(currentIndex, currentQueue.length));
        playbackState.add(transformEvent(PlaybackEvent(), isItemFavourite, itemIndex));
      },
      youtubeID: (finalItem) async {
        mediaItem.add(finalItem.toMediaItem(videoInfo ?? finalItem.toVideoInfoSync(), finalItem.getThumbnailSync(), currentIndex, currentQueue.length));
        playbackState.add(transformEvent(PlaybackEvent(), isItemFavourite, itemIndex));
      },
    );
  }

  // =================================================================================
  //

  //
  // ==============================================================================================
  // ==============================================================================================
  // ================================== QueueManager Overriden ====================================

  @override
  void onIndexChanged(int newIndex, Q newItem) async {
    refreshNotification(newItem);
    await newItem._execute(
      selectable: (finalItem) async {
        await CurrentColor.inst.updatePlayerColorFromTrack(finalItem.track, newIndex);
      },
      youtubeID: (finalItem) async {
        final image = await VideoController.inst.getYoutubeThumbnailAndCache(id: finalItem.id);
        if (image != null && finalItem == currentItem) {
          // -- only extract if same item is still playing, i.e. user didn't skip.
          final color = await CurrentColor.inst.extractPaletteFromImage(image.path);
          if (color != null && finalItem == currentItem) {
            // -- only update if same item is still playing, i.e. user didn't skip.
            CurrentColor.inst.updatePlayerColorFromColor(color.color);
          }
        }
      },
    );
  }

  @override
  void onQueueChanged() async {
    super.onQueueChanged();
    refreshNotification(currentItem);
    await currentQueue._execute(
      selectable: (finalItems) async {
        await QueueController.inst.updateLatestQueue(finalItems.tracks.toList());
      },
      youtubeID: (finalItems) {},
    );
  }

  @override
  void onReorderItems(int currentIndex, Q itemDragged) {
    super.onReorderItems(currentIndex, itemDragged);

    itemDragged._execute(
      selectable: (finalItem) {
        CurrentColor.inst.updatePlayerColorFromTrack(null, currentIndex, updateIndexOnly: true);
      },
      youtubeID: (finalItem) {},
    );

    currentQueue._execute(
      selectable: (finalItems) {
        QueueController.inst.updateLatestQueue(finalItems.tracks.toList());
      },
      youtubeID: (finalItems) {},
    );
  }

  @override
  FutureOr<void> beforeQueueAddOrInsert(Iterable<Q> items) async {
    if (items.firstOrNull is Selectable) {
      if (currentQueue.firstOrNull is YoutubeID) {
        await clearQueue();
        await stop();
      }
    } else if (items.firstOrNull is YoutubeID) {
      if (currentQueue.firstOrNull is Selectable) {
        await clearQueue();
        await stop();
        CurrentColor.inst.resetCurrentPlayingTrack();
      }
    }
  }

  @override
  Future<void> assignNewQueue({
    required int playAtIndex,
    required Iterable<Q> queue,
    bool shuffle = false,
    bool startPlaying = true,
    int? maximumItems,
    void Function()? onQueueEmpty,
    void Function()? onIndexAndQueueSame,
    void Function(List<Q> finalizedQueue)? onQueueDifferent,
  }) async {
    await beforeQueueAddOrInsert(queue);
    await super.assignNewQueue(
      playAtIndex: playAtIndex,
      queue: queue,
      maximumItems: maximumItems,
      onIndexAndQueueSame: onIndexAndQueueSame,
      onQueueDifferent: onQueueDifferent,
      onQueueEmpty: onQueueEmpty,
      startPlaying: startPlaying,
      shuffle: shuffle,
    );
  }

  // ==============================================================================================
  //

  //
  // ==============================================================================================
  // ==============================================================================================
  // ================================== NamidaBasicAudioHandler Overriden ====================================
  @override
  Future<void> setPlayerSpeed(double value) async {
    await Future.wait([
      VideoController.vcontroller.setSpeed(value),
      super.setPlayerSpeed(value),
    ]);
  }

  @override
  Future<void> setPlayerVolume(double value) async {
    await Future.wait([
      VideoController.vcontroller.setVolume(value),
      super.setVolume(value),
    ]);
  }

  @override
  InterruptionAction defaultOnInterruption(InterruptionType type) => settings.playerOnInterrupted[type] ?? InterruptionAction.pause;

  @override
  FutureOr<int> itemToDurationInSeconds(Q item, AudioPlayer player) async {
    return (await item._execute(
          selectable: (finalItem) async {
            final dur = finalItem.track.duration;
            if (dur > 0) {
              return dur;
            } else {
              final ap = AudioPlayer();
              final d = await ap.setFilePath(finalItem.track.path).then((value) => value);
              ap.stop();
              ap.dispose();
              return d?.inSeconds ?? 0;
            }
          },
          youtubeID: (finalItem) async {
            final info = await finalItem.toVideoInfo();
            return info?.duration?.inSeconds ?? 0;
          },
        )) ??
        0;
  }

  @override
  FutureOr<void> onItemMarkedListened(Q item, int listenedSeconds, double listenedPercentage) async {
    await item._execute(
      selectable: (finalItem) async {
        final newTrackWithDate = TrackWithDate(
          dateAdded: currentTimeMS,
          track: finalItem.track,
          source: TrackSource.local,
        );
        HistoryController.inst.addTracksToHistory([newTrackWithDate]);
      },
      youtubeID: (finalItem) {},
    );
  }

  @override
  Future<void> onItemPlay(Q item, int index, bool startPlaying, AudioPlayer player) async {
    await item._execute(
      selectable: (finalItem) async {
        await onItemPlaySelectable(item, finalItem, index, startPlaying, player);
      },
      youtubeID: (finalItem) async {
        await onItemPlayYoutubeID(item, finalItem, index, startPlaying, player);
      },
    );
  }

  Future<void> onItemPlaySelectable(Q pi, Selectable item, int index, bool startPlaying, AudioPlayer player) async {
    final tr = item.track;
    VideoController.inst.updateCurrentVideo(tr);
    WaveformController.inst.generateWaveform(tr);

    /// The whole idea of pausing and playing is due to the bug where [headset buttons/android next gesture] don't get detected.
    try {
      final dur = await player.setAudioSource(tr.toAudioSource(currentIndex, currentQueue.length));
      if (tr.duration == 0) tr.duration = dur?.inSeconds ?? 0;
    } catch (e) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        if (item.track == currentTrack.track) {
          NamidaDialogs.inst.showTrackDialog(tr, isFromPlayerQueue: true, errorPlayingTrack: true, source: QueueSource.playerQueue);
        }
      });
      printy(e, isError: true);
      return;
    }
    await Future.wait([
      player.pause(),
      tryRestoringLastPosition(tr),
    ]);

    if (startPlaying) {
      player.play();
      VideoController.vcontroller.play();
      setVolume(settings.playerVolume.value);
    }

    startSleepAfterMinCount();
    startCounterToAListen(pi);
    increaseListenTime();
    settings.save(lastPlayedTrackPath: tr.path);
    Lyrics.inst.updateLyrics(tr);
  }

  Future<void> onItemPlayYoutubeIDSetQuality(VideoOnlyStream stream, File? cachedFile, {required bool useCache}) async {
    final position = currentPositionMS;
    final wasPlaying = isPlaying;

    if (wasPlaying) await onPauseRaw();

    if (stream.url != null) {
      currentVideoStream.value = stream;
      if (cachedFile != null && useCache) {
        await VideoController.vcontroller.setFile(cachedFile.path, (videoDuration) => false);
      } else {
        await VideoController.vcontroller.setNetworkSource(stream.url!, (videoDuration) => false, disposePrevious: false);
      }
    }

    await seek(position.milliseconds);
    await _waitForAllBuffers();
    if (wasPlaying) {
      await _playAudioThenVideo();
    }
  }

  Future<void> onItemPlayYoutubeID(Q pi, YoutubeID item, int index, bool startPlaying, AudioPlayer player) async {
    YoutubeController.inst.currentYTQualities.clear();
    YoutubeController.inst.updateVideoDetails(item.id);

    currentVideoInfo.value = null;
    currentVideoStream.value = null;
    currentVideoThumbnail.value = null;

    pause();
    await VideoController.vcontroller.dispose();
    try {
      final streams = await YoutubeController.inst.getAvailableStreams(item.id);

      YoutubeController.inst.currentYTQualities
        ..clear()
        ..addAll(streams.videoOnlyStreams ?? []);
      currentVideoInfo.value = streams.videoInfo;

      final vos = streams.videoOnlyStreams;
      final allVideoStream = vos == null || vos.isEmpty ? null : YoutubeController.inst.getPreferredStreamQuality(vos, preferIncludeWebm: false);
      final prefferedVideoStream = allVideoStream;
      final prefferedAudioStream = streams.audioOnlyStreams?.firstWhereEff((e) => e.formatSuffix != 'webm') ?? streams.audioOnlyStreams?.firstOrNull;
      if (prefferedAudioStream?.url != null && prefferedVideoStream?.url != null) {
        currentVideoStream.value = prefferedVideoStream;

        final videoInfo = await item.toVideoInfo();
        // TODO: info is needed for saving audio cache
        // you could use toVideoInfoSync() but u will have to ensure that the info
        // is saved before calling [onItemPlayYoutubeID], otherwise the audio wouldnt be cached properly
        // and may cause re-download because the next time will be providing the real cache name.

        currentVideoInfo.value = videoInfo;
        refreshNotification(pi, currentVideoInfo.value);
        currentVideoThumbnail.value = item.getThumbnailSync();
        final cachedVideo = prefferedVideoStream?.getCachedFile(item.id);
        await Future.wait([
          cachedVideo == null
              ? VideoController.vcontroller.setNetworkSource(prefferedVideoStream!.url!, (videoDuration) => false)
              : VideoController.vcontroller.setFile(cachedVideo.path, (videoDuration) => false),
          player.setAudioSource(LockCachingAudioSource(
            Uri.parse(prefferedAudioStream!.url!),
            cacheFile: File(prefferedAudioStream.cachePath(item.id)),
            tag: item.toMediaItem(currentVideoInfo.value, currentVideoThumbnail.value, index, currentQueue.length),
          )),
        ]);
      }
    } catch (e) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        if (item == currentItem) {
          // show error dialog
        }
      });
      printy(e, isError: true);
      return;
    }

    if (currentVideoInfo.value == null) {
      YoutubeController.inst.fetchVideoDetails(item.id).then((details) {
        if (currentItem == item) {
          currentVideoInfo.value = details;
          refreshNotification(currentItem, currentVideoInfo.value);
        }
      });
    }
    if (currentVideoThumbnail.value == null) {
      VideoController.inst.getYoutubeThumbnailAndCache(id: item.id).then((thumbFile) {
        if (currentItem == item) {
          currentVideoThumbnail.value = thumbFile;
          refreshNotification(currentItem);
        }
      });
    }

    if (startPlaying) {
      setVolume(settings.playerVolume.value);
      await _waitForAllBuffers();
      await play();
    }

    startSleepAfterMinCount();
    startCounterToAListen(pi);
    increaseListenTime();
  }

  @override
  FutureOr<void> onNotificationFavouriteButtonPressed(Q item) async {
    await item._execute(
      selectable: (finalItem) async {
        final newStat = await PlaylistController.inst.favouriteButtonOnPressed(Player.inst.nowPlayingTrack);
        _notificationUpdateItem(
          item: item,
          itemIndex: currentIndex,
          isItemFavourite: newStat,
        );
      },
      youtubeID: (finalItem) {},
    );
  }

  @override
  FutureOr<void> onPlayingStateChange(bool isPlaying) {
    CurrentColor.inst.switchColorPalettes(isPlaying);
  }

  @override
  FutureOr<void> onRepeatForNtimesFinish() {
    settings.save(playerRepeatMode: RepeatMode.none);
  }

  /// TODO: separate yt total listens
  @override
  FutureOr<void> onTotalListenTimeIncrease(int totalTimeInSeconds) async {
    // saves the file each 20 seconds.
    if (totalTimeInSeconds % 20 == 0) {
      _updateTrackLastPosition(currentTrack.track, currentPositionMS);
      await File(AppPaths.TOTAL_LISTEN_TIME).writeAsString(totalTimeInSeconds.toString());
    }
  }

  @override
  FutureOr<void> onItemLastPositionReport(Q? currentItem, int currentPositionMs) async {
    await currentItem?._execute(
      selectable: (finalItem) async {
        await _updateTrackLastPosition(finalItem.track, currentPositionMS);
      },
      youtubeID: (finalItem) async {},
    );
  }

  @override
  void onPlaybackEventStream(PlaybackEvent event) {
    final item = currentItem;
    item?._execute(
      selectable: (finalItem) async {
        final isFav = finalItem.track.isFavourite;
        playbackState.add(transformEvent(event, isFav, currentIndex));
      },
      youtubeID: (finalItem) async {
        playbackState.add(transformEvent(event, false, currentIndex));
      },
    );
  }

  @override
  bool get displayFavouriteButtonInNotification => settings.displayFavouriteButtonInNotification.value;

  @override
  bool get defaultShouldStartPlaying => (settings.playerPlayOnNextPrev.value || isPlaying);

  @override
  bool get enableVolumeFadeOnPlayPause => settings.enableVolumeFadeOnPlayPause.value;

  @override
  bool get playerInfiniyQueueOnNextPrevious => settings.playerInfiniyQueueOnNextPrevious.value;

  @override
  int get playerPauseFadeDurInMilli => settings.playerPauseFadeDurInMilli.value;

  @override
  int get playerPlayFadeDurInMilli => settings.playerPlayFadeDurInMilli.value;

  @override
  bool get playerPauseOnVolume0 => settings.playerPauseOnVolume0.value;

  @override
  RepeatMode get playerRepeatMode => settings.playerRepeatMode.value;

  @override
  bool get playerResumeAfterOnVolume0Pause => settings.playerResumeAfterOnVolume0Pause.value;

  @override
  double get userPlayerVolume => settings.playerVolume.value;

  @override
  bool get jumpToFirstItemAfterFinishingQueue => settings.jumpToFirstTrackAfterFinishingQueue.value;

  @override
  int get listenCounterMarkPlayedPercentage => settings.isTrackPlayedPercentageCount.value;

  @override
  int get listenCounterMarkPlayedSeconds => settings.isTrackPlayedSecondsCount.value;

  @override
  int get maximumSleepTimerMins => kMaximumSleepTimerMins;

  @override
  int get maximumSleepTimerItems => kMaximumSleepTimerTracks;

  @override
  InterruptionAction get onBecomingNoisyEventStream => InterruptionAction.pause;

  // ------------------------------------------------------------
  @override
  Future<void> onSeek(Duration position) async {
    await Future.wait([
      super.onSeek(position),
      VideoController.vcontroller.seek(position),
    ]);
  }

  @override
  Future<void> play() async {
    await onPlay();
  }

  @override
  Future<void> pause() async {
    await onPause();
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final wasPlaying = isPlaying;

    Future<void> plsSeek() async => await onSeek(position);

    Future<void> plsPause() async {
      await Future.wait([
        super.onPauseRaw(),
        VideoController.vcontroller.pause(),
      ]);
    }

    await currentItem?._execute(
      selectable: (finalItem) async {
        // await plsPause();
        await plsSeek();
      },
      youtubeID: (finalItem) async {
        await plsPause();
        await plsSeek();
      },
    );

    await _waitForAllBuffers();
    if (wasPlaying) await _playAudioThenVideo();
  }

  @override
  Future<void> skipToNext([bool? andPlay]) async => await onSkipToNext(andPlay);

  @override
  Future<void> skipToPrevious() async => await onSkipToPrevious();

  @override
  Future<void> skipToQueueItem(int index, [bool? andPlay]) async => await onSkipToQueueItem(index, andPlay);

  @override
  Future<void> stop() async => await onStop();

  @override
  Future<void> fastForward() async => await onFastForward();

  @override
  Future<void> rewind() async => await onRewind();

  @override
  void onBufferOrLoadStart() {
    if (isPlaying) {
      VideoController.vcontroller.pause();
    }
  }

  @override
  void onBufferOrLoadEnd() {
    if (isPlaying) {
      VideoController.vcontroller.play();
    }
  }

  @override
  Future<void> onRealPause() async {
    await VideoController.vcontroller.pause();
  }

  @override
  Future<void> onRealPlay() async {
    await Future.delayed(Duration(milliseconds: _videoPositionSeekDelayMS.abs()));
    await VideoController.vcontroller.play();
  }
}

// ----------------------- Extensions --------------------------
extension TrackToAudioSourceMediaItem on Selectable {
  UriAudioSource toAudioSource(int currentIndex, int queueLength) {
    return AudioSource.uri(
      Uri.parse(track.path),
      tag: toMediaItem(currentIndex, queueLength),
    );
  }

  MediaItem toMediaItem(int currentIndex, int queueLength) {
    final tr = track.toTrackExt();
    return MediaItem(
      id: tr.path,
      title: tr.title,
      displayTitle: tr.title,
      displaySubtitle: tr.hasUnknownAlbum ? tr.originalArtist : "${tr.originalArtist} - ${tr.album}",
      displayDescription: "${currentIndex + 1}/$queueLength",
      artist: tr.originalArtist,
      album: tr.hasUnknownAlbum ? '' : tr.album,
      genre: tr.originalGenre,
      duration: Duration(seconds: tr.duration),
      artUri: Uri.file(File(tr.pathToImage).existsSync() ? tr.pathToImage : AppPaths.NAMIDA_LOGO),
    );
  }
}

extension YoutubeIDToMediaItem on YoutubeID {
  MediaItem toMediaItem(VideoInfo? videoInfo, File? thumbnail, int currentIndex, int queueLength) {
    final vi = videoInfo;
    final artistAndTitle = vi?.name?.splitArtistAndTitle();
    final videoName = vi?.name;
    final channelName = vi?.uploaderName;
    return MediaItem(
      id: vi?.id ?? '',
      title: artistAndTitle?.$2?.keepFeatKeywordsOnly() ?? videoName ?? '',
      artist: artistAndTitle?.$1 ?? channelName?.replaceFirst('- Topic', '').trimAll(),
      album: '',
      genre: '',
      displayTitle: videoName,
      displaySubtitle: channelName,
      displayDescription: "${currentIndex + 1}/$queueLength",
      duration: vi?.duration ?? Duration.zero,
      artUri: Uri.file((thumbnail != null && thumbnail.existsSync()) ? thumbnail.path : AppPaths.NAMIDA_LOGO),
    );
  }
}

extension _PlayableExecuter on Playable {
  FutureOr<T?> _execute<T>({
    required FutureOr<T> Function(Selectable finalItem) selectable,
    required FutureOr<T> Function(YoutubeID finalItem) youtubeID,
  }) async {
    final item = this;
    if (item is Selectable) {
      return await selectable(item);
    } else if (item is YoutubeID) {
      return await youtubeID(item);
    }
    return null;
  }
}

extension _PlayableExecuterList on Iterable<Playable> {
  FutureOr<T?> _execute<T>({
    required FutureOr<T> Function(Iterable<Selectable> finalItems) selectable,
    required FutureOr<T> Function(Iterable<YoutubeID> finalItem) youtubeID,
  }) async {
    final item = firstOrNull;
    if (item is Selectable) {
      return await selectable(cast<Selectable>());
    } else if (item is YoutubeID) {
      return await youtubeID(cast<YoutubeID>());
    }
    return null;
  }
}
