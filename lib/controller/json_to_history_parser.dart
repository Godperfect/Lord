import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import 'package:namida/class/track.dart';
import 'package:namida/class/video.dart';
import 'package:namida/controller/history_controller.dart';
import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/constants.dart';
import 'package:namida/core/enums.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/translations/strings.dart';
import 'package:namida/ui/widgets/custom_widgets.dart';

class JsonToHistoryParser {
  static JsonToHistoryParser get inst => _instance;
  static final JsonToHistoryParser _instance = JsonToHistoryParser._internal();
  JsonToHistoryParser._internal();

  final RxInt parsedHistoryJson = 0.obs;
  final RxInt totalJsonToParse = 0.obs;
  final RxInt addedHistoryJsonToPlaylist = 0.obs;
  final RxBool isParsing = false.obs;
  final RxBool isLoadingFile = false.obs;
  final Rx<TrackSource> currentParsingSource = TrackSource.local.obs;

  void showParsingProgressDialog() {
    NamidaNavigator.inst.navigateDialog(
      Obx(
        () => CustomBlurryDialog(
          normalTitleStyle: true,
          title: isParsing.value ? Language.inst.EXTRACTING_INFO : Language.inst.DONE,
          actions: [
            TextButton(
              child: Text(Language.inst.CONFIRM),
              onPressed: () => NamidaNavigator.inst.closeDialog(),
            )
          ],
          bodyText:
              "${Language.inst.LOADING_FILE}... ${isLoadingFile.value ? '' : Language.inst.DONE}\n\n${parsedHistoryJson.value.formatDecimal(true)} / ${totalJsonToParse.value.formatDecimal(true)} ${Language.inst.PARSED} \n\n${addedHistoryJsonToPlaylist.value.formatDecimal(true)} ${Language.inst.ADDED}",
        ),
      ),
    );
  }

  void _resetValues() {
    totalJsonToParse.value = 0;
    parsedHistoryJson.value = 0;
    addedHistoryJsonToPlaylist.value = 0;
  }

  Future<void> addFileSourceToNamidaHistory(File file, TrackSource source, {bool isMatchingTypeLink = true, bool matchYT = true, bool matchYTMusic = true}) async {
    _resetValues();
    isParsing.value = true;
    isLoadingFile.value = true;

    // TODO: warning to backup history

    /// Removing previous source tracks.
    final isytsource = source == TrackSource.youtube || source == TrackSource.youtubeMusic;
    if (isytsource) {
      HistoryController.inst.removeSourcesTracksFromHistory([TrackSource.youtube, TrackSource.youtubeMusic]);
    } else {
      HistoryController.inst.removeSourcesTracksFromHistory([source]);
    }
    await Future.delayed(Duration.zero);

    final datesAdded = <int>[];

    if (isytsource) {
      currentParsingSource.value = TrackSource.youtube;
      final res = await _parseYTHistoryJsonAndAdd(file, isMatchingTypeLink, matchYT, matchYTMusic);
      datesAdded.addAll(res);
      // await _addYoutubeSourceFromDirectory(isMatchingTypeLink, matchYT, matchYTMusic);
    }
    if (source == TrackSource.lastfm) {
      currentParsingSource.value = TrackSource.lastfm;
      final res = await _addLastFmSource(file);
      datesAdded.addAll(res);
    }
    isParsing.value = false;
    HistoryController.inst.sortHistoryTracks(datesAdded);
    HistoryController.inst.saveHistoryToStorage(datesAdded);
    HistoryController.inst.updateMostPlayedPlaylist();
  }

  /// needs rewrite
  // Future<void> _addYoutubeSourceFromDirectory(bool isMatchingTypeLink, bool matchYT, bool matchYTMusic) async {
  //   totalJsonToParse.value = Directory(k_DIR_YOUTUBE_STATS).listSync().length;

  //   /// Adding tracks that their link matches.
  //   await for (final f in Directory(k_DIR_YOUTUBE_STATS).list()) {
  //     final p = await File(f.path).readAsJson();
  //     final vh = YoutubeVideoHistory.fromJson(p);
  //     final addedTracks = _matchYTVHToNamidaHistory(vh, isMatchingTypeLink, matchYT, matchYTMusic);
  //     addedHistoryJsonToPlaylist.value += addedTracks.length;
  //     parsedHistoryJson.value++;
  //   }
  // }

  /// Returns [daysToSave] to be used by [sortHistoryTracks] && [saveHistoryToStorage].
  Future<List<int>> _parseYTHistoryJsonAndAdd(File file, bool isMatchingTypeLink, bool matchYT, bool matchYTMusic) async {
    _resetValues();
    isParsing.value = true;
    isLoadingFile.value = true;
    await Future.delayed(const Duration(milliseconds: 300));
    final datesToSave = <int>[];

    await file.readAsJsonAndLoop(
      (p, index) async {
        final link = utf8.decode((p['titleUrl']).toString().codeUnits);
        final id = link.length >= 11 ? link.substring(link.length - 11) : link;
        final z = List<Map<String, dynamic>>.from((p['subtitles'] ?? []));

        /// matching in real time, each object.
        await Future.delayed(Duration.zero);
        final yth = YoutubeVideoHistory(
          id,
          (p['title'] as String).replaceFirst('Watched ', ''),
          z.isNotEmpty ? z.first['name'] : '',
          z.isNotEmpty ? utf8.decode((z.first['url']).toString().codeUnits) : '',
          [YTWatch(DateTime.parse(p['time'] ?? 0).millisecondsSinceEpoch, p['header'] == "YouTube Music")],
        );
        final addedDates = _matchYTVHToNamidaHistory(yth, isMatchingTypeLink, matchYT, matchYTMusic);
        addedDates.addAll(addedDates);

        /// extracting and saving to [k_DIR_YOUTUBE_STATS] directory.
        ///  [_addYoutubeSourceFromDirectory] should be called after this.

        // final file = File('$k_DIR_YOUTUBE_STATS$id.txt');
        // final string = await file.exists() ? await File('$k_DIR_YOUTUBE_STATS$id.txt').readAsString() : '';
        // YoutubeVideoHistory? obj = string.isEmpty ? null : YoutubeVideoHistory.fromJson(jsonDecode(string));

        // if (obj == null) {
        //   obj = YoutubeVideoHistory(
        //     id,
        //     (p['title'] as String).replaceFirst('Watched ', ''),
        //     z.isNotEmpty ? z.first['name'] : '',
        //     z.isNotEmpty ? utf8.decode((z.first['url']).toString().codeUnits) : '',
        //     [YTWatch(DateTime.parse(p['time'] ?? 0).millisecondsSinceEpoch, p['header'] == "YouTube Music")],
        //   );
        // } else {
        //   obj.watches.add(YTWatch(DateTime.parse(p['time'] ?? 0).millisecondsSinceEpoch, p['header'] == "YouTube Music"));
        // }
        // await File('$k_DIR_YOUTUBE_STATS$id.txt').writeAsJson(obj);

        parsedHistoryJson.value++;
      },
      onListReady: (response) async {
        totalJsonToParse.value = response?.length ?? 0;
        isLoadingFile.value = false;
      },
    );

    isParsing.value = false;
    return datesToSave;
  }

  /// Returns [daysToSave].
  List<int> _matchYTVHToNamidaHistory(YoutubeVideoHistory vh, bool isMatchingTypeLink, bool matchYT, bool matchYTMusic) {
    final tr = allTracksInLibrary.firstWhereOrNull((trPre) {
      final element = trPre.toTrackExt();
      return isMatchingTypeLink
          ? trPre.youtubeID == vh.id

          /// matching has to meet 2 conditons:
          /// 1. [json title] contains [track.title]
          /// 2. - [json title] contains [track.artistsList.first]
          ///     or
          ///    - [json channel] contains [track.album]
          ///    (useful for nightcore channels, album has to be the channel name)
          ///     or
          ///    - [json channel] contains [track.artistsList.first]
          : vh.title.cleanUpForComparison.contains(element.title.cleanUpForComparison) &&
              (vh.title.cleanUpForComparison.contains(element.artistsList.first.cleanUpForComparison) ||
                  vh.channel.cleanUpForComparison.contains(element.album.cleanUpForComparison) ||
                  vh.channel.cleanUpForComparison.contains(element.artistsList.first.cleanUpForComparison));
    });
    final tracksToAdd = <TrackWithDate>[];
    if (tr != null) {
      for (int i = 0; i < vh.watches.length; i++) {
        final d = vh.watches[i];

        /// sussy checks
        // if the type is youtube music, but the user dont want ytm.
        if (d.isYTMusic && !matchYTMusic) continue;

        // if the type is youtube, but the user dont want yt.
        if (!d.isYTMusic && !matchYT) continue;

        tracksToAdd.add(TrackWithDate(d.date, tr, d.isYTMusic ? TrackSource.youtubeMusic : TrackSource.youtube));
        addedHistoryJsonToPlaylist.value++;
      }
    }
    final daysToSave = HistoryController.inst.addTracksToHistoryOnly(tracksToAdd);
    return daysToSave;
  }

  /// Returns [daysToSave] to be used by [sortHistoryTracks] && [saveHistoryToStorage].
  Future<List<int>> _addLastFmSource(File file) async {
    totalJsonToParse.value = file.readAsLinesSync().length;
    final stream = file.openRead();
    final lines = stream.transform(utf8.decoder).transform(const LineSplitter());

    final totalDaysToSave = <int>[];
    final tracksToAdd = <TrackWithDate>[];

    // used for cases where date couldnt be parsed, so it uses this one as a reference
    int? lastDate;
    await for (final line in lines) {
      parsedHistoryJson.value++;

      /// updates history every 10 tracks
      if (tracksToAdd.length == 10) {
        totalDaysToSave.addAll(HistoryController.inst.addTracksToHistoryOnly(tracksToAdd));
        tracksToAdd.clear();
      }

      // pls forgive me
      await Future.delayed(Duration.zero);

      /// artist, album, title, (dd MMM yyyy HH:mm);
      try {
        final pieces = line.split(',');

        /// matching has to meet 2 conditons:
        /// [csv artist] contains [track.artistsList.first]
        /// [csv title] contains [track.title], anything after ( or [ is ignored.
        final tr = allTracksInLibrary.firstWhereOrNull(
          (trPre) {
            final tr = trPre.toTrackExt();
            return pieces.first.cleanUpForComparison.contains(tr.artistsList.first.cleanUpForComparison) &&
                pieces[2].cleanUpForComparison.contains(tr.title.split('(').first.split('[').first.cleanUpForComparison);
          },
        );
        if (tr != null) {
          // success means: date == trueDate && lastDate is updated.
          // failure means: date == lastDate - 30 seconds || date == 0
          int date = 0;
          try {
            date = DateFormat('dd MMM yyyy HH:mm').parseLoose(pieces.last).millisecondsSinceEpoch;
            lastDate = date;
          } catch (e) {
            if (lastDate != null) {
              date = lastDate - 30000;
            }
          }
          tracksToAdd.add(TrackWithDate(date, tr, TrackSource.lastfm));
          addedHistoryJsonToPlaylist.value++;
        }
      } catch (e) {
        debugPrint(e.toString());
        continue;
      }
    }
    // normally the loop automatically adds every 10 tracks, this one is to ensure adding any tracks left.
    totalDaysToSave.addAll(HistoryController.inst.addTracksToHistoryOnly(tracksToAdd));

    return totalDaysToSave;
  }
}
