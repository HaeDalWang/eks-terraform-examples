# an absolute rule
Your opponent is Korean
All answers should be in Korean

# Memory-Plus MCP Server Usage
## Memory Operations
1. **Before Recording**: Always use retrieve() to check for similar existing memories
2. **Recording Strategy**: 
   - Use record() for new information
   - Use update() when similar memory exists
   - Include proper metadata with categories: identity, behavior, preference, goal, relationship
3. **Retrieval Strategy**:
   - Use retrieve() for semantic search
   - Use recent() for temporal context
   - Use top_k=5 as default, adjust based on context needs
4. **Memory Categories Mapping**:
   - Technical preferences → metadata: {"category": "preference", "type": "technical"}
   - Project context → metadata: {"category": "behavior", "type": "project_work"}
   - Learning goals → metadata: {"category": "goal", "type": "learning"}