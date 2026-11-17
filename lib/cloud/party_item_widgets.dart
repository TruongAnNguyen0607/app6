import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'expense_repository.dart' show parseCents, dollars;
import 'group_details.dart' show memberLabel;
import 'group_repository.dart' show SharedGroup;
import 'party_item_repository.dart';

const Color _ink = Color(0xFF183D36);
const Color _green = Color(0xFF206653);
const Color _cream = Color(0xFFF7F8F2);
const Color _lime = Color(0xFFD9EEAE);
const Color _muted = Color(0xFF71817A);

class PartyItemSelectionPage extends StatefulWidget {
  const PartyItemSelectionPage({
    super.key,
    required this.group,
    required this.userId,
    required this.repository,
  });

  final SharedGroup group;
  final String userId;
  final PartyItemRepository repository;

  @override
  State<PartyItemSelectionPage> createState() => _PartyItemSelectionPageState();
}

class _PartyItemSelectionPageState extends State<PartyItemSelectionPage> {
  late Stream<PartyItemFeed> feed;
  String selectedCategory = 'All';
  String selectedFilter = 'All'; // 'All', 'Unassigned', 'Assigned', 'Mine'
  String searchQuery = '';
  final searchController = TextEditingController();
  bool showPresets = false;

  @override
  void initState() {
    super.initState();
    feed = widget.repository.watchPartyItems(widget.group.id);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void refreshFeed() {
    setState(() {
      feed = widget.repository.watchPartyItems(widget.group.id);
    });
  }

  Future<void> openAddItem({PresetPartyItem? preset}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      builder: (_) => AddPartyItemSheet(
        group: widget.group,
        userId: widget.userId,
        repository: widget.repository,
        initialPreset: preset,
      ),
    );
  }

  Future<void> quickAddPreset(PresetPartyItem preset) async {
    final id = base64UrlEncode(
      List<int>.generate(18, (_) => Random.secure().nextInt(256)),
    );
    final item = PartyItem(
      id: id,
      name: preset.name,
      category: preset.category,
      estimatedCents: preset.estimatedCents,
      quantity: 1,
      createdBy: widget.userId,
    );

    try {
      await widget.repository.addPartyItem(widget.group.id, item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${preset.name} added to party items'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not add item. Check your connection.'),
          ),
        );
      }
    }
  }

  Future<void> toggleClaimItem(PartyItem item) async {
    final newAssignee = item.assignedToUserId == widget.userId
        ? null
        : widget.userId;
    try {
      await widget.repository.assignPartyItem(
        widget.group.id,
        item.id,
        newAssignee,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update assignment. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> assignMember(PartyItem item, String? targetUserId) async {
    try {
      await widget.repository.assignPartyItem(
        widget.group.id,
        item.id,
        targetUserId,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update member assignment.'),
          ),
        );
      }
    }
  }

  Future<void> deleteItem(PartyItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item'),
        content: Text('Are you sure you want to remove "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.repository.deletePartyItem(widget.group.id, item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${item.name} removed')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete item.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        title: Text('${widget.group.name} • Party Items'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: showPresets ? 'Hide catalog' : 'Quick catalog',
            icon: Icon(
              showPresets
                  ? Icons.grid_view_rounded
                  : Icons.library_add_outlined,
              color: _ink,
            ),
            onPressed: () => setState(() => showPresets = !showPresets),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAddItem(),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add party item'),
      ),
      body: StreamBuilder<PartyItemFeed>(
        stream: feed,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: _muted),
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to load party items. Check your connection or rules.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: refreshFeed,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final feedData = snapshot.data!;
          final filteredItems = feedData.filterBy(
            category: selectedCategory,
            selectedFilter: selectedFilter,
            currentUserId: widget.userId,
            searchQuery: searchQuery,
          );

          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isWide ? 32 : 16,
                16,
                isWide ? 32 : 16,
                100,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Overview Header Banner
                      _buildOverviewCard(feedData),
                      const SizedBox(height: 12),
                      Text(
                        feedData.pendingWrites
                            ? 'Changes waiting to sync'
                            : feedData.fromCache
                                ? 'Showing saved items • cloud not confirmed'
                                : 'Up to date',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                      const SizedBox(height: 20),

                      // Presets catalog panel (collapsible or toggled)
                      if (showPresets) ...[
                        _buildPresetCatalogSection(),
                        const SizedBox(height: 24),
                      ],

                      // Search and Filter controls
                      _buildSearchAndFilters(feedData),
                      const SizedBox(height: 20),

                      // Items List or Empty State
                      if (filteredItems.isEmpty)
                        _buildEmptyState(feedData)
                      else if (isWide)
                        _buildWideGrid(filteredItems)
                      else
                        _buildMobileList(filteredItems),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverviewCard(PartyItemFeed data) {
    final progress =
        data.totalCount == 0 ? 0.0 : (data.assignedCount / data.totalCount);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration_outlined, color: _lime, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Party Checklist & Items',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _lime,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${data.assignedCount}/${data.totalCount} Assigned',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: _lime,
              backgroundColor: const Color(0xFF2C564C),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Unassigned items',
                      style: TextStyle(color: Color(0xFFCEE0D6), fontSize: 11),
                    ),
                    Text(
                      '${data.unassignedCount} needed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimated total',
                      style: TextStyle(color: Color(0xFFCEE0D6), fontSize: 11),
                    ),
                    Text(
                      dollars(data.totalEstimatedCents),
                      style: const TextStyle(
                        color: _lime,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCatalogSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E9E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: _green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Browse Popular Party Essentials',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => showPresets = false),
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap any item to add it to your party selection list.',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: presetPartyItems.map((preset) {
              return ActionChip(
                avatar: Icon(preset.icon, size: 18, color: _green),
                label: Text(
                  '${preset.name} (${preset.estimatedCents > 0 ? dollars(preset.estimatedCents) : 'Free/Bring'})',
                  style: const TextStyle(fontSize: 12, color: _ink),
                ),
                backgroundColor: _cream,
                side: const BorderSide(color: Color(0xFFDDE3D5)),
                onPressed: () => quickAddPreset(preset),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(PartyItemFeed feedData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search text field
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            hintText: 'Search party items…',
            prefixIcon: const Icon(Icons.search, color: _muted),
            suffixIcon: searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: _muted),
                    onPressed: () {
                      searchController.clear();
                      setState(() => searchQuery = '');
                    },
                  )
                : null,
          ),
          onChanged: (val) => setState(() => searchQuery = val.trim()),
        ),
        const SizedBox(height: 14),

        // Filter status selector ('All', 'Unassigned', 'Assigned', 'Mine')
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in ['All', 'Unassigned', 'Assigned', 'Mine'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      filter == 'Mine' ? 'Assigned to Me' : filter,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selectedFilter == filter
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: selectedFilter == filter ? Colors.white : _ink,
                      ),
                    ),
                    selected: selectedFilter == filter,
                    selectedColor: _green,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE5E9E1)),
                    showCheckmark: false,
                    onSelected: (bool sel) {
                      if (sel) setState(() => selectedFilter = filter);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Category filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final cat in defaultPartyCategories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: selectedCategory == cat,
                    selectedColor: _lime,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selectedCategory == cat ? _ink : _muted,
                      fontWeight: selectedCategory == cat
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                    side: const BorderSide(color: Color(0xFFE5E9E1)),
                    onSelected: (bool sel) {
                      if (sel) setState(() => selectedCategory = cat);
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(PartyItemFeed feedData) {
    final hasSearch = searchQuery.isNotEmpty ||
        selectedCategory != 'All' ||
        selectedFilter != 'All';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E9E1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch
                ? Icons.filter_alt_off_outlined
                : Icons.checklist_rtl_outlined,
            size: 56,
            color: _muted,
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No matching party items' : 'No party items yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try clearing your search or filter options.'
                : 'Get the party started by adding items or choosing from standard party presets.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 20),
          if (hasSearch)
            OutlinedButton(
              onPressed: () {
                searchController.clear();
                setState(() {
                  searchQuery = '';
                  selectedCategory = 'All';
                  selectedFilter = 'All';
                });
              },
              child: const Text('Reset filters'),
            )
          else ...[
            FilledButton.icon(
              onPressed: () => openAddItem(),
              icon: const Icon(Icons.add),
              label: const Text('Create custom item'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() => showPresets = true),
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Browse popular party items'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWideGrid(List<PartyItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: items
              .map(
                (item) =>
                    SizedBox(width: width, child: _buildPartyItemCard(item)),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildMobileList(List<PartyItem> items) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildPartyItemCard(items[index]),
    );
  }

  Widget _buildPartyItemCard(PartyItem item) {
    final isAssignedToMe = item.assignedToUserId == widget.userId;
    final assigneeName = item.isAssigned
        ? memberLabel(widget.group, item.assignedToUserId!, widget.userId)
        : 'Unassigned';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAssignedToMe
              ? _green
              : item.isAssigned
                  ? const Color(0xFFD3DEC8)
                  : const Color(0xFFE5E9E1),
          width: isAssignedToMe ? 1.8 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _categoryColor(item.category),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _categoryIcon(item.category),
                    color: _ink,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _cream,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.category,
                              style:
                                  const TextStyle(fontSize: 11, color: _muted),
                            ),
                          ),
                          if (item.quantity > 1) ...[
                            const SizedBox(width: 6),
                            Text(
                              '• Qty: ${item.quantity}',
                              style:
                                  const TextStyle(fontSize: 11, color: _muted),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  item.estimatedCents > 0
                      ? dollars(item.estimatedCents * item.quantity)
                      : 'Free/Bring',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _ink,
                    fontSize: 14,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: _muted),
                  onSelected: (val) {
                    if (val == 'delete') deleteItem(item);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete item',
                              style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.notes!,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFEDF0E9)),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  item.isAssigned
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: item.isAssigned ? _green : _muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.isAssigned
                        ? 'Assigned: $assigneeName'
                        : 'Unassigned',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          item.isAssigned ? FontWeight.w600 : FontWeight.normal,
                      color: item.isAssigned ? _ink : _muted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Quick Claim Button
                OutlinedButton.icon(
                  onPressed: () => toggleClaimItem(item),
                  icon: Icon(
                    isAssignedToMe ? Icons.check : Icons.front_hand_outlined,
                    size: 14,
                  ),
                  label: Text(
                    isAssignedToMe ? 'Assigned' : 'Claim',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: isAssignedToMe ? _lime : Colors.transparent,
                    foregroundColor: _ink,
                    side: BorderSide(
                      color: isAssignedToMe ? _green : const Color(0xFFC4D1BF),
                    ),
                  ),
                ),
                PopupMenuButton<String?>(
                  tooltip: 'Assign to specific member',
                  icon: const Icon(Icons.person_add_alt, size: 18, color: _muted),
                  onSelected: (uid) => assignMember(item, uid),
                  itemBuilder: (_) => [
                    const PopupMenuItem<String?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    for (final uid in widget.group.memberIds)
                      PopupMenuItem<String?>(
                        value: uid,
                        child: Text(
                          memberLabel(widget.group, uid, widget.userId),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Food & Drink':
        return const Color(0xFFF7E3D2);
      case 'Equipment':
        return const Color(0xFFE1E8F4);
      case 'Decorations':
        return const Color(0xFFF2E4F7);
      case 'Entertainment':
        return const Color(0xFFE4EBCD);
      default:
        return const Color(0xFFECEFEA);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Food & Drink':
        return Icons.restaurant_rounded;
      case 'Equipment':
        return Icons.inventory_2_outlined;
      case 'Decorations':
        return Icons.celebration_outlined;
      case 'Entertainment':
        return Icons.music_note_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}

class AddPartyItemSheet extends StatefulWidget {
  const AddPartyItemSheet({
    super.key,
    required this.group,
    required this.userId,
    required this.repository,
    this.initialPreset,
  });

  final SharedGroup group;
  final String userId;
  final PartyItemRepository repository;
  final PresetPartyItem? initialPreset;

  @override
  State<AddPartyItemSheet> createState() => _AddPartyItemSheetState();
}

class _AddPartyItemSheetState extends State<AddPartyItemSheet> {
  final nameController = TextEditingController();
  final amountController = TextEditingController();
  final quantityController = TextEditingController(text: '1');
  final notesController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  late String selectedCategory;
  String? assignedUserId;
  bool saving = false;
  String? errorMessage;

  final id = base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  );

  @override
  void initState() {
    super.initState();
    if (widget.initialPreset != null) {
      nameController.text = widget.initialPreset!.name;
      selectedCategory = widget.initialPreset!.category;
      if (widget.initialPreset!.estimatedCents > 0) {
        amountController.text =
            (widget.initialPreset!.estimatedCents / 100).toStringAsFixed(2);
      }
    } else {
      selectedCategory = 'Food & Drink';
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    amountController.dispose();
    quantityController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (!formKey.currentState!.validate()) return;

    final trimmedName = nameController.text.trim();
    final amountText = amountController.text.trim();
    final quantityVal = int.tryParse(quantityController.text.trim()) ?? 1;

    int costCents = 0;
    if (amountText.isNotEmpty) {
      final parsed = parseCents(amountText);
      if (parsed == null) {
        setState(() => errorMessage = 'Enter a valid cost amount (e.g. 12.50).');
        return;
      }
      costCents = parsed;
    }

    setState(() {
      saving = true;
      errorMessage = null;
    });

    try {
      final item = PartyItem(
        id: id,
        name: trimmedName,
        category: selectedCategory,
        estimatedCents: costCents,
        quantity: quantityVal,
        assignedToUserId: assignedUserId,
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        createdBy: widget.userId,
      );

      await widget.repository.addPartyItem(widget.group.id, item);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => errorMessage =
              'Could not save item. Check your connection and permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = defaultPartyCategories.where((c) => c != 'All').toList();

    return PopScope(
      canPop: !saving,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add Party Item',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),

              // Item Name
              TextFormField(
                controller: nameController,
                enabled: !saving,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Item name',
                  hintText: 'e.g. Snacks, Drinks, Paper Cups',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter an item name'
                    : null,
              ),
              const SizedBox(height: 12),

              // Category & Quantity row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration:
                          const InputDecoration(labelText: 'Category'),
                      items: categories
                          .map(
                            (cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(cat),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => selectedCategory = val);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: quantityController,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Qty'),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n < 1 || n > 100) {
                          return '1–100';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Estimated Cost (Optional)
              TextFormField(
                controller: amountController,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Estimated cost (USD, optional)',
                  prefixText: '\$ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (parseCents(v.trim()) == null) {
                    return 'Enter 0.01–1,000,000 or leave empty';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Initial Assignee
              DropdownButtonFormField<String?>(
                initialValue: assignedUserId,
                decoration: const InputDecoration(
                  labelText: 'Assign to (optional)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  for (final uid in widget.group.memberIds)
                    DropdownMenuItem<String?>(
                      value: uid,
                      child: Text(
                        memberLabel(widget.group, uid, widget.userId),
                      ),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (val) => setState(() => assignedUserId = val),
              ),
              const SizedBox(height: 14),

              // Notes / Description
              TextFormField(
                controller: notesController,
                enabled: !saving,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Notes / Details (optional)',
                  hintText: 'e.g. 2 bags of ice, non-dairy options',
                ),
              ),

              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),

              const SizedBox(height: 20),
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(
                  saving ? 'Saving party item…' : 'Save item',
                ),
              ),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
