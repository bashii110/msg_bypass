import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/sms_service.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({Key? key}) : super(key: key);

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _inboxMessages = [];
  List<Map<String, dynamic>> _sentMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMessages();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      final inbox = await SMSService.getInboxMessages();
      final sent = await SMSService.getSentMessages();

      setState(() {
        _inboxMessages = inbox;
        _sentMessages = sent;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Error loading messages: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(date);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMM dd').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inbox), text: 'Inbox'),
            Tab(icon: Icon(Icons.send), text: 'Sent'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildMessageList(_inboxMessages, true),
          _buildMessageList(_sentMessages, false),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showComposeDialog(),
        child: const Icon(Icons.create),
      ),
    );
  }

  Widget _buildMessageList(List<Map<String, dynamic>> messages, bool isInbox) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isInbox ? Icons.inbox : Icons.send,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isInbox ? 'No messages received' : 'No messages sent',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMessages,
      child: ListView.builder(
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return _buildMessageTile(message, isInbox);
        },
      ),
    );
  }

  Widget _buildMessageTile(Map<String, dynamic> message, bool isInbox) {
    final address = message['address'] as String;
    final body = message['body'] as String;
    final date = message['date'] as DateTime;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isInbox ? Colors.blue : Colors.green,
          child: Icon(
            isInbox ? Icons.person : Icons.send,
            color: Colors.white,
          ),
        ),
        title: Text(
          address,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _formatDate(date),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        onTap: () => _showMessageDetail(address, body, date, isInbox),
      ),
    );
  }

  void _showMessageDetail(String address, String body, DateTime date, bool isInbox) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isInbox ? Icons.inbox : Icons.send,
              color: isInbox ? Colors.blue : Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(address)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDate(date),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              Text(body),
            ],
          ),
        ),
        actions: [
          if (isInbox)
            TextButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showComposeDialog(recipient: address);
              },
              icon: const Icon(Icons.reply),
              label: const Text('Reply'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showComposeDialog({String? recipient}) {
    final phoneController = TextEditingController(text: recipient);
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Compose Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                prefixIcon: Icon(Icons.message),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              if (phoneController.text.isEmpty || messageController.text.isEmpty) {
                _showSnackBar('Please fill all fields');
                return;
              }

              Navigator.of(ctx).pop();

              bool sent = await SMSService.sendSMS(
                phoneController.text,
                messageController.text,
              );

              if (sent) {
                _showSnackBar('Message sent successfully');
                _loadMessages();
              } else {
                _showSnackBar('Failed to send message');
              }
            },
            icon: const Icon(Icons.send),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}