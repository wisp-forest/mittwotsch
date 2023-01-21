import 'dart:math';

import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

import 'interaction_extensions.dart';
import 'mittwotsch.dart';

// https://modrinth.com/mod/mythicmetals/version/uF0xLDAH
final _modrinthVersionPattern = RegExp("https://modrinth.com/mod/.+/version/.+");

// https://www.curseforge.com/minecraft/mc-mods/owo-lib/files/3526730
final _curseforgeVersionPattern = RegExp("https://www.curseforge.com/minecraft/mc-mods/.*/files/[0-9]+");

// https://github.com/wisp-forest/owo-lib/releases/tag/0.8.5%2B1.19
final _githubReleasePattern = RegExp("https://github.com/.+/.+/releases/tag/.+");

const _plainAnnouncementPattern = """
```
**{mod_id}** {version}
            
{changelog}
            
{modrinth}{curseforge}{github}
```
""";

final _announcementEmbedCache = _ExpiringCache<AnnouncementToken, _Announcement>(Duration(minutes: 10));

void handleAnnounceCommand(ISlashCommandInteractionEvent event) async {
  await event.respondModal(ModalBuilder("mod-announcement", "Announce mod update")
    // ..componentRows.add(ComponentRowBuilder()
    // .addComponent(TextBuilder))
    ..componentRows.add(ComponentRowBuilder()
      ..addComponent(TextInputBuilder("modrinth-url", TextInputStyle.short, "Modrinth URL")
        ..placeholder = "https://modrinth.com/mod/<slug>/version/<id>"))
    ..componentRows.add(ComponentRowBuilder()
      ..addComponent(TextInputBuilder("curseforge-url", TextInputStyle.short, "CurseForge URL")
        ..required = false
        ..placeholder = "https://curseforge.com/minecraft/mc-mods/<slug>/files/<id>"))
    ..componentRows.add(ComponentRowBuilder()
      ..addComponent(TextInputBuilder("github-url", TextInputStyle.short, "GitHub Release URL")
        ..required = false
        ..placeholder = "https://github.com/<owner>/<repo>/releases/tag/<tag>"))
    ..componentRows.add(ComponentRowBuilder()
      ..addComponent(TextInputBuilder("changelog", TextInputStyle.paragraph, "Changelog")
        ..required = false
        ..placeholder = "Leave blank to adapt Modrinth changelog")));
}

void handleAnnounceModal(IModalInteractionEvent event) async {
  if (event.interaction.customId != "mod-announcement") return;

  final inputComponents = event.interaction.components.expand((e) => e).whereType<IMessageTextInput>();

  final modrinthUrl = inputComponents.byName("modrinth-url").value;
  final curseforgeUrl = inputComponents.byName("curseforge-url").value;
  final githubUrl = inputComponents.byName("github-url").value;
  final changelogInput = inputComponents.byName("changelog").value;

  if (!_modrinthVersionPattern.hasMatch(modrinthUrl)) {
    event.respondError("Invalid Modrinth URL");
    return;
  }

  if (curseforgeUrl.isNotEmpty && !_curseforgeVersionPattern.hasMatch(curseforgeUrl)) {
    event.respondError("Invalid CurseForge URL");
    return;
  }

  if (githubUrl.isNotEmpty && !_githubReleasePattern.hasMatch(githubUrl)) {
    event.respondError("Invalid GitHub release URL");
    return;
  }

  await event.acknowledge();
  final author = event.interaction.userAuthor!;

  final version = await modrinth.getVersion(modrinthUrl.split("/").last);
  if (version == null) {
    event.respondError("Could not query modrinth version", followup: true);
    return;
  }

  final project = await modrinth.getProject(version.projectId);
  if (project == null) {
    event.respondError("Could not query modrinth project", followup: true);
    return;
  }

  final embedId = "publish-${Random().nextInt(1 << 24)}";
  final changelog =
      _formatChangelog(changelogInput.trim().isEmpty ? version.changelog ?? "<no changelog provided>" : changelogInput);

  final iconPalette = OctreeQuantizer(
    (await http
        .get(Uri.parse(project.iconUrl!))
        .then((response) => response.bodyBytes)
        .then(PngDecoder().decode)
        .then((image) => image!)),
    numberOfColors: 5,
  ).palette;

  final embed = EmbedBuilder()
    ..title = "**${project.title}** • Update"
    ..fields = [
      EmbedFieldBuilder("Changelog", changelog),
      EmbedFieldBuilder("Version", version.versionNumber, true),
      EmbedFieldBuilder("Minecraft Versions", version.gameVersions.join(" "), true)
    ]
    ..color = DiscordColor.fromRgb(
      iconPalette.getRed(1).toInt(),
      iconPalette.getGreen(1).toInt(),
      iconPalette.getBlue(1).toInt(),
    )
    ..thumbnailUrl = project.iconUrl
    ..addFooter((footer) {
      footer
        ..iconUrl = author.avatarURL()
        ..text =
            "${author.username}#${author.discriminator} • ${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}";
    });

  var targetChannel = getConfig()["announcement_channel"] as int;

  var response = await event.sendFollowup(ComponentMessageBuilder()
    ..content = _plainAnnouncementPattern
        .replaceAll("{mod_id}", project.title)
        .replaceAll("{version}", version.versionNumber)
        .replaceAll("{changelog}", changelog)
        .replaceAll("{curseforge}", curseforgeUrl.isNotEmpty ? ":curseforge: $curseforgeUrl\n" : "")
        .replaceAll("{modrinth}", modrinthUrl.isNotEmpty ? ":modrinth: $modrinthUrl\n" : "")
        .replaceAll("{github}", githubUrl.isNotEmpty ? ":github: <$githubUrl>\n" : "")
    ..embeds = [
      embed,
      EmbedBuilder()..fields = [EmbedFieldBuilder("Target Channel", "<#$targetChannel>")]
    ]
    ..componentRows = [
      ComponentRowBuilder()
        ..addComponent(ButtonBuilder("Publish", "ask-$embedId", ButtonStyle.primary))
        ..addComponent(ButtonBuilder("Cancel", "cancel-$embedId", ButtonStyle.danger))
    ]);

  _announcementEmbedCache[AnnouncementToken.from(embedId)] =
      _Announcement(embed, Snowflake.value(targetChannel), response, modrinthUrl, curseforgeUrl, githubUrl);
}

void handlePublishCancel(IButtonInteractionEvent event) {
  var eventId = event.interaction.customId;
  if (!eventId.startsWith("cancel-")) return;

  final announcement = _announcementEmbedCache[AnnouncementToken.from(eventId)];
  eventId = eventId.replaceAll("cancel", "publish");

  if (announcement != null) {
    event.acknowledge();

    announcement.previewMessage.delete();
    _announcementEmbedCache._map.remove(eventId);
  } else {
    event.respondError("This announcement has expired");
  }
}

void handleAskForPublish(IButtonInteractionEvent event) {
  var eventId = event.interaction.customId;
  if (!eventId.startsWith("ask-publish-")) return;

  event.respond(ComponentMessageBuilder()
    ..content = " "
    ..componentRows = [
      ComponentRowBuilder()..addComponent(ButtonBuilder("Confirm", eventId.substring(4), ButtonStyle.success))
    ]);
}

void handlePublishConfirm(IButtonInteractionEvent event) async {
  var eventId = event.interaction.customId;
  if (!eventId.startsWith("publish-")) return;

  final announcement = _announcementEmbedCache[AnnouncementToken.from(eventId)];

  if (announcement != null) {
    final channel = await bot.fetchChannel(announcement.channel);

    if (channel is ITextChannel) {
      final buttons = ComponentRowBuilder()
        ..addComponent(LinkButtonBuilder("Modrinth", announcement.modrinthUrl,
            emoji: IBaseGuildEmoji.fromId(Snowflake.value(1065583279346036757))));

      if (announcement.curseforgeUrl.isNotEmpty) {
        buttons.addComponent(LinkButtonBuilder("CurseForge", announcement.curseforgeUrl,
            emoji: IBaseGuildEmoji.fromId(Snowflake.value(909845280323678240))));
      }

      if (announcement.githubUrl.isNotEmpty) {
        buttons.addComponent(LinkButtonBuilder("GitHub", announcement.githubUrl,
            emoji: IBaseGuildEmoji.fromId(Snowflake.value(1031975515239755806))));
      }

      final post = channel.sendMessage(ComponentMessageBuilder()
        ..embeds = [announcement.embed]
        ..componentRows = [buttons]);

      if (channel.channelType == ChannelType.guildNews) {
        post.then((value) => value.crossPost());
      }

      event.respond(ComponentMessageBuilder()
        ..componentRows = []
        ..embeds = [
          EmbedBuilder()
            ..title = "Announcement published"
            ..color = DiscordColor.green
        ]);
    } else {
      event.respondError("The target channel is not a text channel");
    }
  } else {
    event.respondError("This announcement has expired");
  }
}

String _formatChangelog(String changelog) {
  final lines = changelog.split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!line.trimLeft().startsWith("#")) continue;

    lines[i] = "**${line.replaceAll("#", "").trim()}**";
  }

  return lines.join("\n");
}

class _Announcement {
  final EmbedBuilder embed;
  final Snowflake channel;
  final IMessage previewMessage;
  final String modrinthUrl;
  final String curseforgeUrl;
  final String githubUrl;
  _Announcement(this.embed, this.channel, this.previewMessage, this.modrinthUrl, this.curseforgeUrl, this.githubUrl);
}

class AnnouncementToken {
  String token;

  AnnouncementToken(this.token);

  factory AnnouncementToken.from(String eventId) {
    return AnnouncementToken(eventId.substring(eventId.lastIndexOf("-") + 1));
  }

  @override
  bool operator ==(Object other) {
    return other is AnnouncementToken && other.token == token;
  }

  @override
  int get hashCode {
    return token.hashCode;
  }
}

class _ExpiringCache<K, V> {
  final Map<K, V> _map = {};
  final Duration _retainDuration;

  _ExpiringCache(this._retainDuration);

  void operator []=(K key, V value) {
    _map[key] = value;
    Future.delayed(_retainDuration, () => _map.remove(key));
  }

  V? operator [](K key) {
    return _map[key];
  }
}
