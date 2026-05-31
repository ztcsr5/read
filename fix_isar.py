import os
import re

directory = os.path.join("lib", "data", "models")
if not os.path.exists(directory):
    print(f"Directory {directory} does not exist.")
    exit(0)
for filename in os.listdir(directory):
    if filename.endswith(".g.dart"):
        filepath = os.path.join(directory, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Replace large integers
        content = re.sub(r'(?<!\.)\b([1-9]\d{15,19})\b', '1234567890', content)
        content = re.sub(r'(?<!\.)\b-([1-9]\d{15,19})\b', '-1234567890', content)
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Fixed {filename}")
