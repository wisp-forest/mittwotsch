import 'dart:math';

import 'package:intl/intl.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_interactions/nyxx_interactions.dart';

import 'interaction_extensions.dart';
import 'mittwotsch.dart';

// https://modrinth.com/mod/mythicmetals/version/uF0xLDAH
final _modrinthVersionPattern = RegExp("https://modrinth.com/mod/.+/version/.*");

// https://www.curseforge.com/minecraft/mc-mods/owo-lib/files/3526730
final _curseforgeVersionPattern = RegExp("https://www.curseforge.com/minecraft/mc-mods/.*/files/[0-9]+");

const _plainAnnouncementPattern = """
```
**{mod_id}** {version}
            
{changelog}
            
:modrinth: {modrinth_url}
:curseforge: {curseforge_url}
```
""";

final _announcementEmbedCache = _ExpiringCache<String, _Announcement>(Duration(minutes: 10));

void handleAnnounceCommand(ISlashCommandInteractionEvent event) async {
  await event.respondModal(ModalBuilder("mod-announcement", "Announce mod update")
    ..componentRows.add(
        ComponentRowBuilder()..addComponent(TextInputBuilder("modrinth-url", TextInputStyle.short, "Modrinth URL")))
    ..componentRows.add(
        ComponentRowBuilder()..addComponent(TextInputBuilder("curseforge-url", TextInputStyle.short, "CurseForge URL")))
    ..componentRows.add(ComponentRowBuilder()
      ..addComponent(TextInputBuilder("changelog", TextInputStyle.paragraph, "Changelog")..required = false)));
}

void handleAnnounceModal(IModalInteractionEvent event) async {
  final inputComponents = event.interaction.components.expand((e) => e).whereType<IMessageTextInput>();

  final modrinthUrl = inputComponents.byName("modrinth-url").value;
  final curseforgeUrl = inputComponents.byName("curseforge-url").value;
  final changelogInput = inputComponents.byName("changelog").value;

  if (!_modrinthVersionPattern.hasMatch(modrinthUrl)) {
    event.respondError("Invalid modrinth URL");
    return;
  }

  if (!_curseforgeVersionPattern.hasMatch(curseforgeUrl)) {
    event.respondError("Invalid curseforge URL");
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

  final embed = EmbedBuilder()
    ..title = "**${project.title}** • Update"
    ..fields = [
      EmbedFieldBuilder("Changelog", changelog),
      EmbedFieldBuilder("Version", version.versionNumber, true),
      EmbedFieldBuilder("Minecraft Versions", version.gameVersions.join(" "), true)
    ]
    ..thumbnailUrl = project.iconUrl
    ..addFooter((footer) {
      footer
        ..iconUrl = author.avatarURL()
        ..text =
            "${author.username}#${author.discriminator} • ${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}";
    });

  var targetChannel = getConfig()["announcement_channel"] as int;
  _announcementEmbedCache[embedId] = _Announcement(embed, Snowflake.value(targetChannel), modrinthUrl, curseforgeUrl);

  await event.sendFollowup(MessageBuilder()
    ..content = _plainAnnouncementPattern
        .replaceAll("{mod_id}", project.title)
        .replaceAll("{version}", version.versionNumber)
        .replaceAll("{changelog}", changelog)
        .replaceAll("{curseforge_url}", curseforgeUrl)
        .replaceAll("{modrinth_url}", modrinthUrl));

  event.sendFollowup(ComponentMessageBuilder()
    ..embeds = [embed, EmbedBuilder()..description = "<#$targetChannel>"]
    ..componentRows = [ComponentRowBuilder()..addComponent(ButtonBuilder("Publish", embedId, ButtonStyle.primary))]);
}

void handlePublishButton(IButtonInteractionEvent event) async {
  var eventId = event.interaction.customId;
  if (!eventId.startsWith("publish-")) return;

  final announcement = _announcementEmbedCache[eventId];

  if (announcement != null) {
    final channel = await getBot().fetchChannel(announcement.channel);

    if (channel is ITextChannel) {
      final post = channel.sendMessage(ComponentMessageBuilder()
        ..embeds = [announcement.embed]
        ..componentRows = [
          ComponentRowBuilder()
            ..addComponent(LinkButtonBuilder("Modrinth", announcement.modrinthUrl,
                emoji: IBaseGuildEmoji.fromId(Snowflake.value(909845280340443196))))
            ..addComponent(LinkButtonBuilder("CurseForge", announcement.curseforgeUrl,
                emoji: IBaseGuildEmoji.fromId(Snowflake.value(909845280323678240))))
        ]);

      if (channel.channelType == ChannelType.guildNews) {
        post.then((value) => value.crossPost());
      }

      event.respondEmbed(EmbedBuilder()
        ..title = "Announcement published"
        ..color = DiscordColor.green);
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
  final String modrinthUrl;
  final String curseforgeUrl;
  _Announcement(this.embed, this.channel, this.modrinthUrl, this.curseforgeUrl);
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
