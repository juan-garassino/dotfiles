---
name: ag-knowledge
description: >
  Helps design and build knowledge graph systems — extracting entities and
  relationships from text, code, or documents, storing them in a graph structure,
  and querying or reasoning over them. Covers NetworkX for in-memory graphs,
  Neo4j for persistent graph databases, LlamaIndex Knowledge Graphs for RAG,
  and Graph RAG patterns where an LLM reasons over a knowledge graph. Use when
  building a knowledge graph, extracting structured relationships from unstructured
  data, implementing graph-based retrieval, connecting a knowledge graph to an
  LLM agent, or visualizing entity relationships. Triggers include "build a
  knowledge graph", "extract entities and relationships", "graph rag", "connect
  documents into a graph", "knowledge graph from my codebase", "entity extraction",
  "relationship extraction", "graph database", "neo4j", "networkx knowledge graph",
  "reason over a graph", "link entities across documents".
---

# ag-knowledge — Knowledge Graph Builder

You help design and build systems that extract structured knowledge from
unstructured sources — text, code, documents, conversations — store it as
a graph of entities and relationships, and make it queryable by humans or
LLM agents.

---

## When to Use a Knowledge Graph vs Plain RAG

| Situation | Use |
|-----------|-----|
| "Find documents about X" | Plain vector RAG |
| "How is X related to Y?" | Knowledge graph |
| "What does X depend on?" | Knowledge graph |
| "Summarize everything about X across 50 docs" | Graph RAG |
| "Find the path between X and Z" | Knowledge graph |
| "Which entities appear together most?" | Knowledge graph |

---

## Core Concepts

```
Entity:       A named thing — person, concept, file, function, place
Relationship: A typed connection between two entities — "calls", "depends_on",
              "authored_by", "contradicts", "is_a"
Triple:       (entity_1, relationship, entity_2) — the atomic unit
Graph:        A collection of triples
```

---

## Stack Options

| Option | Best for | Persistence |
|--------|---------|------------|
| **NetworkX** | In-memory, analysis, prototyping | No (save to JSON/pickle) |
| **Neo4j** | Production, large graphs, Cypher queries | Yes |
| **LlamaIndex KG** | RAG + knowledge graph combined | Pluggable |
| **Plain dict** | Tiny graphs, quick scripts | No |

---

## LLM-Based Entity & Relationship Extraction

```python
import anthropic
import json

client = anthropic.Anthropic()

EXTRACT_PROMPT = """Extract all entities and relationships from the text below.

Return JSON only, no markdown:
{{
  "entities": [
    {{"id": "unique_slug", "name": "Display Name", "type": "person|concept|place|org|file|function|other"}}
  ],
  "relationships": [
    {{"from": "entity_id", "to": "entity_id", "type": "relationship_type", "description": "optional detail"}}
  ]
}}

Text:
{text}"""


def extract_graph(text: str, model: str = "claude-sonnet-4-6") -> dict:
    """Extract entities and relationships from a text chunk."""
    response = client.messages.create(
        model=model,
        max_tokens=2048,
        messages=[{"role": "user", "content": EXTRACT_PROMPT.format(text=text)}]
    )
    raw = response.content[0].text.strip()
    # Strip markdown fences if present
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    return json.loads(raw.strip())


def extract_from_documents(docs: list[str], chunk_size: int = 2000) -> dict:
    """Extract and merge a knowledge graph from multiple documents."""
    all_entities = {}
    all_relationships = []

    for doc in docs:
        # Process in chunks
        for i in range(0, len(doc), chunk_size):
            chunk = doc[i:i+chunk_size]
            result = extract_graph(chunk)

            for entity in result.get("entities", []):
                eid = entity["id"]
                if eid not in all_entities:
                    all_entities[eid] = entity

            for rel in result.get("relationships", []):
                if rel not in all_relationships:
                    all_relationships.append(rel)

    return {"entities": list(all_entities.values()), "relationships": all_relationships}
```

---

## NetworkX Implementation

```python
import networkx as nx
import json

def build_networkx_graph(extracted: dict) -> nx.DiGraph:
    """Build a NetworkX directed graph from extracted entities and relationships."""
    G = nx.DiGraph()

    for entity in extracted["entities"]:
        G.add_node(
            entity["id"],
            name=entity["name"],
            type=entity.get("type", "unknown")
        )

    for rel in extracted["relationships"]:
        if rel["from"] in G and rel["to"] in G:
            G.add_edge(
                rel["from"], rel["to"],
                type=rel["type"],
                description=rel.get("description", "")
            )

    return G


def query_graph(G: nx.DiGraph, entity_id: str, depth: int = 2) -> dict:
    """Get all entities and relationships within N hops of an entity."""
    if entity_id not in G:
        return {"error": f"Entity '{entity_id}' not found"}

    # BFS within depth
    neighbors = nx.ego_graph(G, entity_id, radius=depth)
    return {
        "center": G.nodes[entity_id],
        "entities": [{"id": n, **G.nodes[n]} for n in neighbors.nodes],
        "relationships": [
            {"from": u, "to": v, **G.edges[u, v]}
            for u, v in neighbors.edges
        ]
    }


def find_path(G: nx.DiGraph, from_id: str, to_id: str) -> list:
    """Find the shortest relationship path between two entities."""
    try:
        path = nx.shortest_path(G, from_id, to_id)
        result = []
        for i in range(len(path) - 1):
            edge = G.edges[path[i], path[i+1]]
            result.append({
                "from": G.nodes[path[i]]["name"],
                "relationship": edge.get("type", "related_to"),
                "to": G.nodes[path[i+1]]["name"],
            })
        return result
    except nx.NetworkXNoPath:
        return []


def save_graph(G: nx.DiGraph, path: str):
    data = nx.node_link_data(G)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def load_graph(path: str) -> nx.DiGraph:
    with open(path) as f:
        data = json.load(f)
    return nx.node_link_graph(data)
```

---

## Graph RAG — LLM Querying Over the Graph

```python
def graph_rag_query(G: nx.DiGraph, question: str,
                     model: str = "claude-sonnet-4-6") -> str:
    """
    Answer a question by giving the LLM a subgraph as context.
    1. Extract key entities from the question
    2. Pull their neighborhood from the graph
    3. Format as context for the LLM
    """
    # Step 1: Find relevant entities
    entity_names = {data["name"].lower(): nid
                    for nid, data in G.nodes(data=True)}
    question_lower = question.lower()
    relevant_ids = [nid for name, nid in entity_names.items()
                    if name in question_lower]

    # Step 2: Get subgraph
    context_triples = []
    for eid in relevant_ids[:5]:  # limit to top 5 matches
        subgraph = query_graph(G, eid, depth=2)
        for rel in subgraph["relationships"]:
            from_name = G.nodes[rel["from"]]["name"]
            to_name = G.nodes[rel["to"]]["name"]
            context_triples.append(
                f"{from_name} --[{rel['type']}]--> {to_name}"
            )

    context = "\n".join(set(context_triples[:50]))  # dedupe, limit

    # Step 3: Answer with context
    prompt = f"""Use the following knowledge graph context to answer the question.
If the answer isn't in the graph, say so.

Knowledge graph:
{context}

Question: {question}"""

    response = client.messages.create(
        model=model,
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.content[0].text


---

## Visualization

```python
def visualize_graph(G: nx.DiGraph, save_path: str = "graph.html",
                     max_nodes: int = 100):
    """Interactive graph visualization using pyvis."""
    try:
        from pyvis.network import Network
    except ImportError:
        print("pip install pyvis")
        return

    net = Network(height="750px", width="100%", directed=True,
                  bgcolor="#1a1a2e", font_color="white")

    # Color by entity type
    type_colors = {
        "person": "#e94560", "concept": "#0f3460",
        "file": "#533483", "function": "#e94560",
        "org": "#16213e", "other": "#533483",
    }

    for node, data in list(G.nodes(data=True))[:max_nodes]:
        color = type_colors.get(data.get("type", "other"), "#533483")
        net.add_node(node, label=data.get("name", node),
                     color=color, title=f"Type: {data.get('type', '?')}")

    for u, v, data in G.edges(data=True):
        if u in net.get_nodes() and v in net.get_nodes():
            net.add_edge(u, v, label=data.get("type", ""),
                         title=data.get("description", ""))

    net.save_graph(save_path)
    print(f"Graph saved: {save_path} — open in browser")
```

---

## Codebase Knowledge Graph

Special case: extracting a knowledge graph from source code.

```python
import ast
import os

def extract_python_graph(project_root: str) -> dict:
    """
    Extract a knowledge graph from a Python codebase.
    Nodes: modules, classes, functions
    Edges: imports, calls, inherits, defines
    """
    entities = {}
    relationships = []

    for root, _, files in os.walk(project_root):
        for fname in files:
            if not fname.endswith(".py"):
                continue
            fpath = os.path.join(root, fname)
            module_id = fpath.replace(project_root, "").replace("/", ".").strip(".")

            entities[module_id] = {"id": module_id, "name": module_id, "type": "module"}

            try:
                with open(fpath) as f:
                    tree = ast.parse(f.read())
            except SyntaxError:
                continue

            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        relationships.append({
                            "from": module_id, "to": alias.name,
                            "type": "imports"
                        })
                elif isinstance(node, ast.FunctionDef):
                    fn_id = f"{module_id}.{node.name}"
                    entities[fn_id] = {"id": fn_id, "name": node.name, "type": "function"}
                    relationships.append({"from": module_id, "to": fn_id, "type": "defines"})
                elif isinstance(node, ast.ClassDef):
                    cls_id = f"{module_id}.{node.name}"
                    entities[cls_id] = {"id": cls_id, "name": node.name, "type": "class"}
                    relationships.append({"from": module_id, "to": cls_id, "type": "defines"})
                    for base in node.bases:
                        if isinstance(base, ast.Name):
                            relationships.append({
                                "from": cls_id, "to": base.id, "type": "inherits"
                            })

    return {"entities": list(entities.values()), "relationships": relationships}
```

---

## Reference Files

- `references/neo4j_patterns.md` — Neo4j/Cypher patterns, bulk import, graph algorithms (PageRank, community detection), LlamaIndex Neo4j integration
