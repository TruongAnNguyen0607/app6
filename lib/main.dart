import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

const ink = Color(0xFF183D36);
const muted = Color(0xFF71817A);
const green = Color(0xFF206653);
const cream = Color(0xFFF7F8F2);
const lime = Color(0xFFD9EEAE);

String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Together • Shared expenses',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        surface: Colors.white,
      ),
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -1.2,
        ),
        headlineSmall: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.6,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyMedium: TextStyle(fontSize: 14, color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cream,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const HomePage(),
  );
}

class Group {
  Group(this.name, this.note, this.memberNames, this.icon, this.color);
  final String name, note;
  final List<String> memberNames;
  final IconData icon;
  final Color color;
  int get members => memberNames.length;
}

class Expense {
  Expense(this.name, this.group, this.cents, this.payer);
  final String name, payer;
  final Group group;
  final int cents;
}

class PartyItem {
  PartyItem(this.name, {this.quantity = 1, this.notes = '', this.claimedBy});
  final String name;
  final int quantity;
  final String notes;
  String? claimedBy; // null = unclaimed, else a name from group.memberNames
}

class PartyList {
  PartyList(this.title, this.group, this.items);
  final String title;
  final Group group;
  final List<PartyItem> items;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selected = 0;
  int saved = 72000;
  final groups = [
    Group(
      'Weekend in Lisbon',
      'A little adventure together',
      ['You', 'Alex', 'Sam', 'Priya'],
      Icons.flight_takeoff_rounded,
      const Color(0xFFE4EBCD),
    ),
    Group(
      'The dinner club',
      'Good food, better company',
      ['You', 'Alex', 'Sam', 'Priya', 'Morgan'],
      Icons.restaurant_rounded,
      const Color(0xFFF7E3D2),
    ),
    Group(
      'Our happy place',
      'Home is a team effort',
      ['You', 'Alex', 'Sam'],
      Icons.cottage_outlined,
      const Color(0xFFE1E8F4),
    ),
  ];
  late final List<Expense> expenses = [
    Expense('Dinner at Alma', groups[1], 12800, 'You'),
    Expense('A place to stay', groups[0], 36000, 'Alex'),
    Expense('Weekly groceries', groups[2], 6450, 'You'),
  ];
  late final List<PartyList> partyLists = [
    PartyList('Lisbon send-off party', groups[0], [
      PartyItem(
        'Sparkling wine',
        quantity: 2,
        notes: 'Something bubbly for the toast',
      ),
      PartyItem('Portuguese custard tarts', quantity: 12, claimedBy: 'Alex'),
      PartyItem('Playlist & speaker', notes: 'Upbeat, not too loud'),
      PartyItem('Ice', quantity: 2, claimedBy: 'You'),
    ]),
  ];

  int balance(Group group) => expenses
      .where((e) => e.group == group)
      .fold(
        0,
        (sum, e) =>
            sum +
            (e.payer == 'You'
                ? e.cents - e.cents ~/ e.group.members
                : -(e.cents ~/ e.group.members)),
      );
  int get owed =>
      groups.map(balance).where((n) => n > 0).fold(0, (a, b) => a + b);
  int get owing =>
      -groups.map(balance).where((n) => n < 0).fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (value) =>
                  setState(() => selected = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Overview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  label: 'Groups',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  label: 'Activity',
                ),
                NavigationDestination(
                  icon: Icon(Icons.flag_outlined),
                  label: 'Goals',
                ),
              ],
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) sidebar(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 40 : 22),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        topBar(wide),
                        const SizedBox(height: 34),
                        if (selected == 0)
                          ...overview()
                        else if (selected == 1) ...[
                          heading(
                            'Your groups',
                            'Life is better when you share it.',
                            action: OutlinedButton.icon(
                              onPressed: addGroup,
                              icon: const Icon(Icons.add),
                              label: const Text('New group'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          groupGrid(),
                        ] else if (selected == 2) ...[
                          heading(
                            'Activity',
                            'All the little things you split together.',
                            action: OutlinedButton.icon(
                              onPressed: startPartyList,
                              icon: const Icon(Icons.celebration_outlined),
                              label: const Text('Start a party list'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Party lists',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          partyListGrid(),
                          const SizedBox(height: 30),
                          Text(
                            'Expenses',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          expenseList(),
                        ] else ...[
                          heading(
                            'Shared goals',
                            'Big plans start with small contributions.',
                          ),
                          const SizedBox(height: 24),
                          goalCard(),
                        ],
                        const SizedBox(height: 28),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.favorite_border, size: 14, color: muted),
                            SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'Less money talk. More good times.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sidebar() => Container(
    width: 226,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: Color(0xFFE7EBE3))),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(fit: BoxFit.scaleDown, child: brand()),
        const SizedBox(height: 48),
        const Padding(
          padding: EdgeInsets.only(left: 14, bottom: 14),
          child: Text(
            'YOUR SPACE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
        for (final (i, label, icon) in [
          (0, 'Overview', Icons.grid_view_rounded),
          (1, 'My groups', Icons.people_outline),
          (2, 'Activity', Icons.receipt_long_outlined),
          (3, 'Shared goals', Icons.flag_outlined),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                selected: selected == i,
                selectedTileColor: const Color(0xFFEAF1E4),
                selectedColor: green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(icon, size: 21),
                title: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => setState(() => selected = i),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cream,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.wb_sunny_outlined, color: green),
              const SizedBox(height: 10),
              const Text(
                'Make room for memories.',
                style: TextStyle(color: ink, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'We’ll help with the splitting.',
                style: TextStyle(fontSize: 12),
              ),
              TextButton(
                onPressed: addGroup,
                child: const Text('Start a group  ↗'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            CircleAvatar(
              backgroundColor: lime,
              child: Text(
                'JD',
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jamie Davis',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w600),
                  ),
                  Text('Personal space', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget brand() => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.spa_rounded, color: green, size: 30),
      SizedBox(width: 8),
      Text(
        'together',
        style: TextStyle(
          color: ink,
          fontSize: 25,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      Text(
        '.',
        style: TextStyle(
          color: green,
          fontSize: 30,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  Widget topBar(bool wide) => Row(
    children: [
      if (!wide)
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: brand()),
          ),
        )
      else
        const Text(
          'YOUR EVERYDAY, SHARED',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      if (wide) const Spacer() else const SizedBox(width: 12),
      if (wide)
        const Padding(
          padding: EdgeInsets.only(right: 18),
          child: Text('Demo workspace', style: TextStyle(fontSize: 12)),
        ),
      FilledButton.icon(
        onPressed: addExpense,
        icon: const Icon(Icons.add, size: 18),
        label: Text(wide ? 'Add expense' : 'Expense'),
      ),
    ],
  );

  Widget heading(String title, String subtitle, {Widget? action}) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 18,
    runSpacing: 12,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text(subtitle),
        ],
      ),
      ?action,
    ],
  );

  List<Widget> overview() => [
    heading(
      'Good things, shared.',
      'Hey Jamie, here’s where everything stands.',
    ),
    const SizedBox(height: 26),
    LayoutBuilder(
      builder: (context, constraints) {
        final items = [balanceCard(), goalCard(compact: true)];
        return constraints.maxWidth > 680
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: items[0]),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: items[1]),
                ],
              )
            : Column(
                children: [items[0], const SizedBox(height: 16), items[1]],
              );
      },
    ),
    const SizedBox(height: 32),
    sectionHeader(
      'Your groups',
      '${groups.length} little circles',
      'New group',
      addGroup,
    ),
    const SizedBox(height: 16),
    groupGrid(),
    const SizedBox(height: 30),
    sectionHeader(
      'Recent activity',
      'The latest in your circles',
      'View all',
      () => setState(() => selected = 2),
    ),
    const SizedBox(height: 14),
    expenseList(),
  ];

  Widget sectionHeader(
    String title,
    String subtitle,
    String action,
    VoidCallback onTap,
  ) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      TextButton(onPressed: onTap, child: Text('$action  →')),
    ],
  );

  Widget balanceCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              'Your total balance',
              style: TextStyle(color: Color(0xFFCEE0D6)),
            ),
            Spacer(),
            Icon(Icons.account_balance_wallet_outlined, color: lime, size: 23),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${owed >= owing ? '+' : '−'}${money((owed - owing).abs())}',
          style: const TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          owed >= owing
              ? 'Looking good. You’re owed overall.'
              : 'A little settling up to do.',
          style: const TextStyle(color: Color(0xFFB5CFC0), fontSize: 12),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Divider(color: Color(0xFF426159), height: 1),
        ),
        Row(
          children: [
            Expanded(
              child: balanceMetric(
                'You are owed',
                owed,
                Icons.south_west,
                lime,
              ),
            ),
            Expanded(
              child: balanceMetric(
                'You owe',
                owing,
                Icons.north_east,
                const Color(0xFFF0BE9A),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget balanceMetric(String label, int amount, IconData icon, Color color) =>
      Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFCEE0D6),
                    fontSize: 11,
                  ),
                ),
                Text(
                  money(amount),
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget goalCard({bool compact = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFFECF0DE),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFE0E6D2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.landscape_outlined, color: green, size: 28),
            const SizedBox(width: 10),
            const Text(
              'A LITTLE EVERY DAY',
              style: TextStyle(
                color: green,
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Contribute to goal',
              onPressed: contribute,
              icon: const Icon(Icons.arrow_outward, color: green, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Next stop: Lisbon',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 5),
        const Text(
          'A shared fund for your next adventure.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Flexible(
              child: Text(
                money(saved),
                style: const TextStyle(
                  color: ink,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Flexible(child: Text('  of \$1,200')),
            const SizedBox(width: 12),
            Text(
              '${(saved / 1200).round()}%',
              style: const TextStyle(color: green, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (saved / 120000).clamp(0, 1),
            minHeight: 7,
            color: green,
            backgroundColor: const Color(0xFFD7DFC7),
          ),
        ),
        const SizedBox(height: 14),
        if (compact)
          const Text(
            '4 friends. One unforgettable trip.',
            style: TextStyle(fontSize: 11),
          )
        else
          FilledButton.icon(
            onPressed: contribute,
            icon: const Icon(Icons.add),
            label: const Text('Add contribution'),
          ),
      ],
    ),
  );

  Widget groupGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 760
          ? 3
          : constraints.maxWidth > 480
          ? 2
          : 1;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: groups
            .map(
              (g) => SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                child: groupCard(g),
              ),
            )
            .toList(),
      );
    },
  );

  Widget groupCard(Group g) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE5E9E1)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => openGroup(g),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: g.color,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(g.icon, color: ink),
                ),
                const Spacer(),
                const Icon(Icons.north_east, size: 18, color: muted),
              ],
            ),
            const SizedBox(height: 20),
            Text(g.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(g.note, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 20),
            Row(
              children: [
                for (int i = 0; i < (g.members > 3 ? 3 : g.members); i++)
                  Align(
                    widthFactor: .8,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: [
                        const Color(0xFFE6EBD6),
                        const Color(0xFFF1DFCE),
                        const Color(0xFFDDE6EE),
                      ][i],
                      child: Text(
                        g.memberNames[i][0],
                        style: const TextStyle(fontSize: 10, color: ink),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                Text(
                  '${g.members} members',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: Color(0xFFEDF0E9)),
            ),
            Text(
              balance(g) == 0
                  ? 'All settled up'
                  : balance(g) > 0
                  ? 'You’re owed ${money(balance(g))}'
                  : 'You owe ${money(-balance(g))}',
              style: TextStyle(
                color: balance(g) < 0 ? const Color(0xFF996340) : green,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget partyListGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 760
          ? 3
          : constraints.maxWidth > 480
          ? 2
          : 1;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: partyLists
            .map(
              (p) => SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 16) / columns,
                child: partyListCard(p),
              ),
            )
            .toList(),
      );
    },
  );

  Widget partyListCard(PartyList list) {
    final claimed = list.items.where((i) => i.claimedBy != null).length;
    final total = list.items.length;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE5E9E1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openPartyList(list),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: lime,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.celebration_outlined, color: ink),
                  ),
                  const Spacer(),
                  const Icon(Icons.north_east, size: 18, color: muted),
                ],
              ),
              const SizedBox(height: 20),
              Text(list.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(list.group.name, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 16),
              Text(
                total == 0
                    ? 'No items yet'
                    : '$claimed of $total items claimed',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : claimed / total,
                  minHeight: 7,
                  color: green,
                  backgroundColor: const Color(0xFFD7DFC7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget expenseList({Group? group}) {
    final list = expenses
        .where((e) => group == null || e.group == group)
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E9E1)),
      ),
      child: list.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(30),
              child: Text('No expenses yet. Add your first shared moment.'),
            )
          : Column(
              children: [
                for (int i = 0; i < list.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 22,
                      endIndent: 22,
                      color: Color(0xFFEDF0E9),
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 9,
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: list[i].group.color.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(list[i].group.icon, color: ink, size: 20),
                    ),
                    title: Text(
                      list[i].name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    subtitle: Text(
                      '${list[i].group.name}\n${list[i].payer} paid • Split equally',
                      style: const TextStyle(
                        fontSize: 11,
                        color: muted,
                        height: 1.6,
                      ),
                    ),
                    trailing: Text(
                      money(list[i].cents),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ink,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget partyItemList(PartyList list, StateSetter setSheetState) {
    final items = list.items;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E9E1)),
      ),
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(30),
              child: Text('No items yet. Add the first thing to bring.'),
            )
          : Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 22,
                      endIndent: 22,
                      color: Color(0xFFEDF0E9),
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 9,
                    ),
                    title: Text(
                      '×${items[i].quantity}  ${items[i].name}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    subtitle: items[i].notes.isEmpty
                        ? null
                        : Text(
                            items[i].notes,
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                    trailing: items[i].claimedBy == null
                        ? OutlinedButton(
                            onPressed: () => setSheetState(
                              () => items[i].claimedBy = 'You',
                            ),
                            child: const Text("I'll bring this"),
                          )
                        : items[i].claimedBy == 'You'
                        ? TextButton(
                            onPressed: () => setSheetState(
                              () => items[i].claimedBy = null,
                            ),
                            child: const Text('Undo'),
                          )
                        : Text(
                            'Claimed by ${items[i].claimedBy}',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> openGroup(Group group) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: cream,
    builder: (context) => FractionallySizedBox(
      heightFactor: .75,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${group.members} members • ${group.note}'),
            const SizedBox(height: 24),
            expenseList(group: group),
            const SizedBox(height: 20),
            const Text(
              'Expenses are split equally among group members. This preview uses sample data; changes last for this session.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> openPartyList(PartyList list) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cream,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => FractionallySizedBox(
          heightFactor: .75,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        list.title,
                        style: Theme.of(sheetContext).textTheme.headlineSmall,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final item = await addPartyItem();
                        if (item != null) {
                          setSheetState(() => list.items.add(item));
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add item'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${list.group.name} • ${list.items.length} items'),
                const SizedBox(height: 24),
                partyItemList(list, setSheetState),
                const SizedBox(height: 20),
                const Text(
                  'Only you can claim or release items on this device. '
                  'This preview uses sample data; changes last for this session.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The sheet lives in the overlay, outside the main widget subtree, so
    // changes made inside it don't repaint partyListCard's progress bar on
    // their own — force that now that the sheet (mutating the same live
    // list/items) has closed.
    if (mounted) setState(() {});
  }

  Future<void> startPartyList() async {
    final title = TextEditingController();
    final form = GlobalKey<FormState>();
    Group group = groups.first;
    final result = await showDialog<PartyList>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a party list'),
        content: SizedBox(
          width: 360,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Party title'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Give your party a title'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<Group>(
                  initialValue: group,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: groups
                      .map(
                        (g) =>
                            DropdownMenuItem(value: g, child: Text(g.name)),
                      )
                      .toList(),
                  onChanged: (v) => group = v!,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  PartyList(title.text.trim(), group, []),
                );
              }
            },
            child: const Text('Create list'),
          ),
        ],
      ),
    );
    if (result != null && mounted) setState(() => partyLists.insert(0, result));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    title.dispose();
    if (result != null && mounted) await openPartyList(result);
  }

  Future<void> addExpense() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final form = GlobalKey<FormState>();
    Group group = groups.first;
    String payer = 'You';
    final result = await showDialog<Expense>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add an expense'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'What was it for?',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter an expense name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: amount,
                    decoration: const InputDecoration(
                      labelText: 'Amount (USD)',
                      prefixText: '\$ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: validateAmount,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<Group>(
                    initialValue: group,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Group'),
                    items: groups
                        .map(
                          (g) =>
                              DropdownMenuItem(value: g, child: Text(g.name)),
                        )
                        .toList(),
                    onChanged: (v) => group = v!,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: payer,
                    decoration: const InputDecoration(labelText: 'Paid by'),
                    items: ['You', 'Alex']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => payer = v!,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Split equally with everyone in the group.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  Expense(
                    name.text.trim(),
                    group,
                    (double.parse(amount.text.trim()) * 100).round(),
                    payer,
                  ),
                );
              }
            },
            child: const Text('Save expense'),
          ),
        ],
      ),
    );
    if (result != null && mounted) setState(() => expenses.insert(0, result));
    // Dialog controllers are released after the closing transition finishes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    amount.dispose();
  }

  String? validateAmount(String? value) {
    final n = double.tryParse(value?.trim() ?? '');
    if (n == null || !n.isFinite || n <= 0 || n > 1000000) {
      return 'Enter an amount between 0.01 and 1,000,000';
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value!.trim())) {
      return 'Use up to two decimal places';
    }
    return null;
  }

  Future<void> addGroup() async {
    final name = TextEditingController();
    final members = TextEditingController(text: '2');
    final form = GlobalKey<FormState>();
    final result = await showDialog<Group>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a new circle'),
        content: SizedBox(
          width: 360,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Group name'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Give your group a name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: members,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of members (including you)',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 2 || n > 50
                        ? 'Choose between 2 and 50 members'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  Group(
                    name.text.trim(),
                    'New memories in the making',
                    [
                      'You',
                      for (int i = 2; i <= int.parse(members.text); i++)
                        'Member $i',
                    ],
                    Icons.people_outline,
                    const Color(0xFFE4EBCD),
                  ),
                );
              }
            },
            child: const Text('Create group'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        groups.add(result);
        selected = 1;
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    members.dispose();
  }

  Future<PartyItem?> addPartyItem() async {
    final name = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final notes = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<PartyItem>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add an item'),
        content: SizedBox(
          width: 360,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Item name'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter an item name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 99
                        ? 'Choose between 1 and 99'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  PartyItem(
                    name.text.trim(),
                    quantity: int.parse(quantity.text.trim()),
                    notes: notes.text.trim(),
                  ),
                );
              }
            },
            child: const Text('Add item'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    quantity.dispose();
    notes.dispose();
    return result;
  }

  Future<void> contribute() async {
    final amount = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('A little closer to Lisbon'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Record a contribution to your shared fund. No money is transferred.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: amount,
                decoration: const InputDecoration(
                  labelText: 'Contribution (USD)',
                  prefixText: '\$ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: validateAmount,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  (double.parse(amount.text.trim()) * 100).round(),
                );
              }
            },
            child: const Text('Add contribution'),
          ),
        ],
      ),
    );
    if (result != null && mounted) setState(() => saved += result);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    amount.dispose();
  }
}
