import os
import re

def fix_g_dart_files(directory):
    pattern = re.compile(r'(\s+id:\s*)(-?\d+)(,?)')
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.g.dart'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()

                def repl(match):
                    prefix = match.group(1)
                    num_str = match.group(2)
                    suffix = match.group(3)
                    num = int(num_str)
                    # MAX_SAFE_INTEGER is 9007199254740991
                    # If it exceeds, we replace it with a smaller hash or the truncated value.
                    # Since we only use Mock on web, we can just replace it with a small int hash.
                    if abs(num) > 9007199254740991:
                        new_num = hash(num_str) % 9007199254740991
                        return f'{prefix}{new_num}{suffix}'
                    return match.group(0)

                new_content = pattern.sub(repl, content)

                if new_content != content:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Patched: {filepath}")

if __name__ == '__main__':
    fix_g_dart_files('D:/Gemini反重力/read/lib/data/models')
