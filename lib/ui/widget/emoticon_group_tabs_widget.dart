import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/data/data.dart';
import 'package:flutter_nga/data/entity/emoticon.dart';
import 'package:flutter_nga/ui/widget/font_style_widget.dart';
import 'package:flutter_nga/ui/widget/nga_emoticon_image.dart';

class EmoticonGroupTabsWidget extends StatefulWidget {
  const EmoticonGroupTabsWidget({this.callback, super.key});
  final InputCallback? callback;

  @override
  State<EmoticonGroupTabsWidget> createState() => _EmoticonGroupTabsState();
}

class _EmoticonGroupTabsState extends State<EmoticonGroupTabsWidget> {
  final List<Tab> _tabs = [];
  final List<Widget> _tabBarViews = [];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            isScrollable: true,
            labelColor: Theme.of(context).textTheme.bodyLarge?.color,
            unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
            tabs: _tabs,
          ),
          Expanded(child: TabBarView(children: _tabBarViews)),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final list = Data().emoticonRepository.getEmoticonGroups();
    _tabs.addAll(list.map((group) => Tab(text: group.name)));
    _tabBarViews.addAll(
      list.map(
        (group) =>
            _EmoticonGroupWidget(group: group, callback: widget.callback),
      ),
    );
  }
}

class _EmoticonGroupWidget extends StatelessWidget {
  const _EmoticonGroupWidget({this.group, this.callback});

  final EmoticonGroup? group;
  final InputCallback? callback;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 6,
      children: group!.expressionList
          .map(
            (expression) => Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => callback?.call(expression.content, "", false),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  // 面板表情固定边长；NgaEmoticonImage 同时负责深色主题下
                  // 黑色线稿表情的反相，与正文里的表情表现一致
                  child: NgaEmoticonImage(url: expression.url, size: 34),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
