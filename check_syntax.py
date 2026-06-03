import sys
import re

def check():
    with open('lib/data/parsers/legado_parser.dart', 'r', encoding='utf-8') as f:
        text = f.read()

    # Extremely naive but effective dart string/comment remover for brace checking
    text = re.sub(r'//.*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    
    # Remove raw strings r'...' and r"..."
    text = re.sub(r"r'[^']*'", '', text)
    text = re.sub(r'r"[^"]*"', '', text)
    
    # Remove regular strings '...' and "..."
    # Warning: doesn't perfectly handle nested escaping, but good enough
    text = re.sub(r"'([^'\\]|\\.)*'", '', text)
    text = re.sub(r'"([^"\\]|\\.)*"', '', text)

    stack = []
    for i, c in enumerate(text):
        if c in '{[(':
            stack.append((c, i))
        elif c in '}])':
            if not stack:
                print(f'Unbalanced {c} at {i}')
                sys.exit(1)
            last_c, last_i = stack.pop()
            if (last_c == '{' and c != '}') or (last_c == '[' and c != ']') or (last_c == '(' and c != ')'):
                print(f'Mismatch: {last_c} at {last_i} and {c} at {i}')
                print(text[last_i-50:last_i+50])
                sys.exit(1)
    if stack:
        print(f'Unclosed {stack}')
        sys.exit(1)
    else:
        print('Syntax OK for braces')

if __name__ == '__main__':
    check()
