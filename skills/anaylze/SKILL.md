---
name: analyze
description: Explains code with visual diagrams and analogies. Use when explaining how code works or when the user asks how something works.
---

When explaining code, always:
1. check ~/Canonical/workspace/kernel_readdoc compare to current folder what haven't be documented 
2. choose a subsystems according to your order
3. Draw an ASCII diagram of whole subsystem stack
4. Explain each layer and component
5. Draw an ASCII diagram of how it works
6. export result to an hackmd file
7. program an test case by python with bpftrace to verify the work flow step by step
   which mark pass or faild for each step. And export md(file name README.md) and test case to the ~/canonical/workspace/kernel_readdoc
   relevant place(create folder if not exist). And add a commit then push 
8. check if still I still have token. If yes, do the next topic without asking.
 
Keep the explanation practical and easy to follow.
