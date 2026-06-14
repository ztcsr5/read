import os

keywords = ['上一章', '下一章', 'progress', 'slider', '覆盖', 'animation', 'header', 'footer', 'margin', 'padding', '最近更新', '100章', '999']

with open('search_results.txt', 'w', encoding='utf-8') as out:
    path = 'lib/features/reader/views/reader_page.dart'
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as file:
            for i, line in enumerate(file, 1):
                line_strip = line.strip()
                for kw in keywords:
                    if kw in line_strip:
                        out.write(f"{i}: {line_strip}\n")
                        break
    except Exception as e:
        out.write(f"Error: {str(e)}\n")

print("Done searching reader_page.dart.")
