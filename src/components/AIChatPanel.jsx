import React, { useState, useEffect, useRef } from 'react';
import { Bot, Send, User, Sparkles, Loader2 } from 'lucide-react';
import { sendAiChat } from '../services/aiApi.js';

export default function AIChatPanel() {
  const [messages, setMessages] = useState([
    { role: 'ai', text: 'Hello! I am your AI Clinical Assistant. How can I help you today?' }
  ]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const scrollRef = useRef(null);

  // Auto-scroll to bottom
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSendMessage = async (e) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    const userText = input.trim();
    const newMessages = [...messages, { role: 'user', text: userText }];
    setMessages(newMessages);
    setInput('');
    setIsLoading(true);

    try {
      const data = await sendAiChat(newMessages);
      setMessages(prev => [...prev, { role: 'ai', text: data.response }]);
    } catch (err) {
      console.error('Chat error:', err);
      setMessages(prev => [...prev, { role: 'ai', text: 'Sorry, I encountered an error connecting to the AI service. Please try again later.' }]);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="card" style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: 0, overflow: 'hidden' }}>
      {/* Header */}
      <div style={{ padding: '16px', background: 'var(--grad-primary)', color: 'white', display: 'flex', alignItems: 'center', gap: '10px' }}>
        <Bot size={20} />
        <div style={{ flex: 1 }}>
          <h3 style={{ margin: 0, fontSize: '1rem', fontWeight: 600 }}>AI Clinical Assistant</h3>
          <p style={{ margin: 0, fontSize: '0.7rem', opacity: 0.8, display: 'flex', alignItems: 'center', gap: '4px' }}>
            <Sparkles size={10} /> Online & Ready
          </p>
        </div>
      </div>

      {/* Messages */}
      <div 
        ref={scrollRef}
        style={{ flex: 1, overflowY: 'auto', padding: '16px', display: 'flex', flexDirection: 'column', gap: '12px' }}
      >
        {messages.map((m, i) => (
          <div key={i} style={{ display: 'flex', gap: '10px', flexDirection: m.role === 'ai' ? 'row' : 'row-reverse' }}>
            <div style={{ 
              width: '28px', height: '28px', borderRadius: '50%', 
              background: m.role === 'ai' ? 'var(--clr-primary-light)' : '#e2e8f0',
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0
            }}>
              {m.role === 'ai' ? <Bot size={14} color="var(--clr-primary)" /> : <User size={14} color="#64748b" />}
            </div>
            <div style={{ 
              background: m.role === 'ai' ? '#f8fafc' : 'var(--clr-primary)',
              color: m.role === 'ai' ? '#1e293b' : 'white',
              padding: '10px 14px', borderRadius: '12px', fontSize: '0.88rem',
              maxWidth: '85%', boxShadow: '0 2px 4px rgba(0,0,0,0.05)',
              border: m.role === 'ai' ? '1px solid #e2e8f0' : 'none',
              borderTopLeftRadius: m.role === 'ai' ? '2px' : '12px',
              borderTopRightRadius: m.role === 'user' ? '2px' : '12px'
            }}>
              {m.text}
            </div>
          </div>
        ))}
        {isLoading && (
          <div style={{ display: 'flex', gap: '10px' }}>
            <div style={{ 
              width: '28px', height: '28px', borderRadius: '50%', 
              background: 'var(--clr-primary-light)', display: 'flex', alignItems: 'center', justifyContent: 'center'
            }}>
              <Bot size={14} color="var(--clr-primary)" />
            </div>
            <div style={{ background: '#f8fafc', padding: '10px 14px', borderRadius: '12px', border: '1px solid #e2e8f0' }}>
              <Loader2 size={16} className="animate-spin" color="var(--clr-primary)" />
            </div>
          </div>
        )}
      </div>

      {/* Input */}
      <div style={{ padding: '16px', borderTop: '1px solid #eee' }}>
        <form onSubmit={handleSendMessage} style={{ display: 'flex', gap: '8px' }}>
          <input 
            type="text" 
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={isLoading}
            placeholder="Ask about schedule, patients..."
            style={{ 
              flex: 1, border: '1px solid #e2e8f0', borderRadius: '20px', 
              padding: '8px 16px', fontSize: '0.88rem', outline: 'none',
              background: isLoading ? '#f1f5f9' : 'white'
            }}
          />
          <button 
            type="submit" 
            disabled={!input.trim() || isLoading}
            style={{ 
              width: '36px', height: '36px', borderRadius: '50%', 
              background: 'var(--clr-primary)', color: 'white', 
              display: 'flex', alignItems: 'center', justifyContent: 'center', 
              border: 'none', cursor: 'pointer', transition: 'all 0.2s',
              opacity: (!input.trim() || isLoading) ? 0.5 : 1
            }}
          >
            <Send size={16} />
          </button>
        </form>
      </div>
    </div>
  );
}
