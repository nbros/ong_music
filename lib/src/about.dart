import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(AboutPage());
}

class AboutPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Jonathan Ong',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Jonathan Ong is a classically trained pianist from Sydney, Australia who streams on Twitch. '
            'He is known for his multi-instrumental loops, virtuosic piano playing and engaging live performances.',
            style: TextStyle(
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://www.twitch.tv/jonathanong')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset('assets/twitch.svg', height: 24.0),
                          const SizedBox(width: 8),
                          const Text('Twitch'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 19),
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://www.theorangejacketbrigade.com/albums')),
                      child: const Row(
                        children: [
                          Icon(Icons.album),
                          SizedBox(width: 8),
                          Text('Albums'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://www.youtube.com/@JonathanOng/videos')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset('assets/youtube.svg', height: 24.0),
                          const SizedBox(width: 8),
                          const Text('YouTube'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://www.tiktok.com/@jongmusic/')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset('assets/tiktok2.svg', height: 24.0),
                          const SizedBox(width: 8),
                          const Text('TikTok'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://twitter.com/jonathanong77')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset('assets/twitter.svg', height: 24.0),
                          const SizedBox(width: 8),
                          const Text('Twitter'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://instagram.com/jonathanong77')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset('assets/instagram.svg', height: 24.0),
                          const SizedBox(width: 8),
                          const Text('Instagram'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://jonathanong.threadless.com/')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset("assets/jacket.png", height: 24.0),
                          const SizedBox(width: 8),
                          const Text('Merch'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () => launchUrl(Uri.parse('https://stukem.com/collections/jonathanong')),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset("assets/ongZoom.png", height: 24.0),
                          const SizedBox(width: 8),
                          const Text("Stickers"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        //
        //
        //
        //
      ),
    );
  }
}
