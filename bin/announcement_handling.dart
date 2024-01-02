import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:modrinth_api/modrinth_api.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';

import 'interaction_extensions.dart';
import 'mittwotsch.dart';

// https://modrinth.com/mod/mythicmetals/version/uF0xLDAH
final _modrinthVersionPattern = RegExp("https://modrinth.com/mod/(.+)/version/(.+)");

// https://www.curseforge.com/minecraft/mc-mods/owo-lib/files/3526730
final _curseforgeVersionPattern =
    RegExp("https://(?:(?:www|legacy).)?curseforge.com/minecraft/mc-mods/.*/files/[0-9]+");

// https://github.com/wisp-forest/owo-lib/releases/tag/0.8.5%2B1.19
final _githubReleasePattern = RegExp("https://github.com/.+/.+/releases/tag/.+");

const _plainAnnouncementPattern = """
```
**{mod_id}** {version}
            
{changelog}
            
{modrinth}{curseforge}{github}
```
""";

void registerAnnouncementCommand(CommandsPlugin commands) {
  commands.addCommand(ChatCommand(
    "announce",
    "Announce a new mod release",
    id("announce", (InteractionChatContext context) async {
      var modalResponse = await context.getModal(title: "Announce mod update", components: [
        TextInputBuilder(
          customId: "modrinth-url",
          style: TextInputStyle.short,
          label: "Modrinth URL",
          placeholder: "https://modrinth.com/mod/<slug>/version/<id>",
        ),
        TextInputBuilder(
          customId: "curseforge-url",
          style: TextInputStyle.short,
          label: "CurseForge URL",
          isRequired: false,
          placeholder: "https://curseforge.com/minecraft/mc-mods/<slug>/files/<id>",
        ),
        TextInputBuilder(
          customId: "github-url",
          style: TextInputStyle.short,
          label: "GitHub Release URL",
          isRequired: false,
          placeholder: "https://github.com/<owner>/<repo>/releases/tag/<tag>",
        ),
        TextInputBuilder(
          customId: "changelog",
          style: TextInputStyle.paragraph,
          label: "Changelog",
          isRequired: false,
          placeholder: "Leave blank to adapt Modrinth changelog",
        ),
      ]);

      final modrinthUrl = modalResponse["modrinth-url"]!;
      final curseforgeUrl = modalResponse["curseforge-url"]!;
      final githubUrl = modalResponse["github-url"]!;
      final changelogInput = modalResponse["changelog"]!;

      if (!_modrinthVersionPattern.hasMatch(modrinthUrl)) {
        context.respondError("Invalid Modrinth URL", level: ResponseLevel.hint);
        return;
      }

      if (curseforgeUrl.isNotEmpty && !_curseforgeVersionPattern.hasMatch(curseforgeUrl)) {
        context.respondError("Invalid CurseForge URL", level: ResponseLevel.hint);
        return;
      }

      if (githubUrl.isNotEmpty && !_githubReleasePattern.hasMatch(githubUrl)) {
        context.respondError("Invalid GitHub release URL", level: ResponseLevel.hint);
        return;
      }

      final modrinthMatch = _modrinthVersionPattern.firstMatch(modrinthUrl)!;
      final version = await modrinth.projects.getVersions(modrinthMatch[1]!).then((value) => value!
          .cast<ModrinthVersion?>()
          .firstWhere((element) => element!.id == modrinthMatch[2] || element.versionNumber == modrinthMatch[2],
              orElse: () => null));

      if (version == null) {
        context.respondError("Could not query modrinth version", level: ResponseLevel.hint);
        return;
      }

      final project = await modrinth.projects.get(version.projectId);
      if (project == null) {
        context.respondError("Could not query modrinth project", level: ResponseLevel.hint);
        return;
      }

      final changelog = _formatChangelog(
          changelogInput.trim().isEmpty ? version.changelog ?? "<no changelog provided>" : changelogInput);
      if (changelog.length > 1024) {
        context.respondError("Changelog is too long (>1024 characters)", level: ResponseLevel.hint);
        return;
      }

      final iconPalette = OctreeQuantizer(
        (await http
            .get(Uri.parse(project.iconUrl!))
            .then((response) => response.bodyBytes)
            .then(decodeImage)
            .then((image) => image!)),
        numberOfColors: 5,
      ).palette;

      final announcementEmbed = EmbedBuilder()
        ..title = "**${project.title}** • Update"
        ..fields = [
          EmbedFieldBuilder(name: "Changelog", value: changelog, isInline: false),
          EmbedFieldBuilder(name: "Version", value: version.versionNumber, isInline: true),
          EmbedFieldBuilder(name: "Minecraft Versions", value: version.gameVersions.join(" "), isInline: true)
        ]
        ..color = DiscordColor.fromRgb(
          iconPalette.getRed(1).toInt(),
          iconPalette.getGreen(1).toInt(),
          iconPalette.getBlue(1).toInt(),
        )
        // TODO field promotion?
        ..thumbnail = EmbedThumbnailBuilder(url: Uri.parse(project.iconUrl!))
        ..footer = EmbedFooterBuilder(
            text: "@${context.user.username} • ${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}",
            iconUrl: context.user.avatar.url);

      var targetChannel = botConfig["announcement_channel"] as int;
      var doPublish = await context.getConfirmation(
        MessageBuilder(
          content: _plainAnnouncementPattern
              .replaceAll("{mod_id}", project.title)
              .replaceAll("{version}", version.versionNumber)
              .replaceAll("{changelog}", changelog)
              .replaceAll("{curseforge}", curseforgeUrl.isNotEmpty ? ":curseforge: $curseforgeUrl\n" : "")
              .replaceAll("{modrinth}", modrinthUrl.isNotEmpty ? ":modrinth: $modrinthUrl\n" : "")
              .replaceAll("{github}", githubUrl.isNotEmpty ? ":github: <$githubUrl>\n" : ""),
          embeds: [
            announcementEmbed,
            EmbedBuilder(fields: [
              EmbedFieldBuilder(name: "Target Channel", value: "<#$targetChannel>", isInline: false),
            ])
          ],
        ),
        values: const {true: "Publish", false: "Cancel"},
        level: ResponseLevel.hint,
      );

      if (!doPublish) return;

      if (!await context.getConfirmation(
        MessageBuilder(content: " "),
        values: const {true: "Publish", false: "Cancel"},
        level: ResponseLevel.hint,
      )) {
        return;
      }

      final channel = await bot.channels.get(Snowflake(botConfig["announcement_channel"] as int));
      final wfEmoji = await bot.guilds.get(Snowflake(825828008644313089)).then((value) => value.emojis);

      if (channel is TextChannel) {
        final buttons = <MessageComponentBuilder>[
          ButtonBuilder.link(
            label: "Modrinth",
            url: Uri.parse(modrinthUrl),
            emoji: await wfEmoji.get(Snowflake(1065583279346036757)),
          )
        ];

        if (curseforgeUrl.isNotEmpty) {
          buttons.add(ButtonBuilder.link(
            label: "CurseForge",
            url: Uri.parse(curseforgeUrl),
            emoji: await wfEmoji.get(Snowflake(909845280323678240)),
          ));
        }

        if (githubUrl.isNotEmpty) {
          buttons.add(ButtonBuilder.link(
            label: "GitHub",
            url: Uri.parse(githubUrl),
            emoji: await wfEmoji.get(Snowflake(1031975515239755806)),
          ));
        }

        final message = MessageBuilder()
          ..embeds = [announcementEmbed]
          ..components = [ActionRowBuilder(components: buttons)];

        if (botConfig["release_announcement_role"] is int) {
          message.content = "<@&${botConfig["release_announcement_role"]}>";
        }

        final post = channel.sendMessage(message);
        if (channel.type == ChannelType.guildAnnouncement) {
          post.then((value) => value.crosspost());
        }

        context.respondEmbed(
          EmbedBuilder()
            ..title = "Announcement published"
            ..color = DiscordColor(0x00ff00),
          level: ResponseLevel.hint,
        );
      } else {
        context.respondError("The target channel is not a text channel");
      }
    }),
    checks: [
      PermissionsCheck(Permissions.administrator, allowsOverrides: false),
      GuildCheck.id(Snowflake(botConfig["privileged_guild"] as int)),
    ],
  ));
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
