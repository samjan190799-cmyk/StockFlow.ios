import os
import re
import sys
import subprocess
from dotenv import load_dotenv
from google import genai

# Подгружаем Rich для красивого CLI
try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.markdown import Markdown
    from rich.syntax import Syntax
    from rich.prompt import Prompt, Confirm
except ImportError:
    # Фоллбек, если rich не установлен
    class Console:
        def print(self, *args, **kwargs):
            print(*args)
    class Panel:
        @classmethod
        def fit(cls, text, title=""):
            return f"=== {title} ===\n{text}\n================="
    class Markdown:
        def __init__(self, text): self.text = text
        def __repr__(self): return self.text
    # Dummy prompt implementation
    class Prompt:
        @classmethod
        def ask(cls, text, default=""):
            res = input(f"{text} [{default}]: ")
            return res if res else default
    class Confirm:
        @classmethod
        def ask(cls, text):
            res = input(f"{text} (y/n): ").lower()
            return res.startswith('y')

# Загружаем переменные среды
load_dotenv()

from agents import DesignerAgent, PlannerAgent, CoderAgent, VerifierAgent, RussianReminderAgent

console = Console()

def get_workspace_files(base_dir: str) -> list[str]:
    """Рекурсивный поиск файлов в проекте (исключая .git, .venv, build, xcodeproj)"""
    exclude_dirs = {".git", ".venv", "build", ".xcodeproj", ".idea", "node_modules", "AgentOrchestrator"}
    exclude_files = {".DS_Store", "project.yml"}
    
    files_list = []
    for root, dirs, files in os.walk(base_dir):
        # Исключаем ненужные папки
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        for file in files:
            if file not in exclude_files and not file.startswith("."):
                rel_path = os.path.relpath(os.path.join(root, file), base_dir)
                files_list.append(rel_path.replace(os.sep, "/"))
    return files_list

def apply_diff_blocks(file_path: str, content: str, blocks_text: str) -> tuple[str, bool]:
    """Парсит блоки SEARCH/REPLACE и применяет их к содержимому файла"""
    # Нормализуем переводы строк
    content = content.replace('\r\n', '\n')
    blocks_text = blocks_text.replace('\r\n', '\n')
    
    pattern = r"<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)\n>>>>>>> REPLACE"
    matches = re.findall(pattern, blocks_text, re.DOTALL)
    
    if not matches:
        # Проверим, вдруг модель выдала код целиком без блоков
        if "=======" not in blocks_text and len(blocks_text.strip()) > 50:
            console.print("[yellow]Предупреждение: Изменения не содержат блоков SEARCH/REPLACE. Попытка перезаписать файл целиком.[/yellow]")
            return blocks_text, True
        return content, False
        
    modified_content = content
    success = True
    
    for search_block, replace_block in matches:
        # Если блок поиска пустой - это новый файл или вставка в конец
        if not search_block.strip():
            modified_content += "\n" + replace_block
            continue
            
        occurrences = modified_content.count(search_block)
        if occurrences == 0:
            console.print(f"[red]Ошибка: Блок поиска не найден в файле {file_path}:[/red]")
            console.print(Panel(search_block, title="Искомый текст (не найден)"))
            success = False
        elif occurrences > 1:
            console.print(f"[red]Ошибка: Блок поиска найден несколько раз ({occurrences}) в файле {file_path}:[/red]")
            console.print(Panel(search_block, title="Неоднозначный блок"))
            success = False
        else:
            modified_content = modified_content.replace(search_block, replace_block)
            
    return modified_content, success

def display_diff(file_path: str, original: str, modified: str):
    """Отображает красивое превью изменений для пользователя"""
    original_lines = original.replace('\r\n', '\n').split('\n')
    modified_lines = modified.replace('\r\n', '\n').split('\n')
    
    import difflib
    diff = list(difflib.unified_diff(
        original_lines, 
        modified_lines, 
        fromfile=f"a/{file_path}", 
        tofile=f"b/{file_path}",
        lineterm=""
    ))
    
    if not diff:
        console.print("[yellow]Изменений не обнаружено.[/yellow]")
        return
        
    diff_text = "\n".join(diff)
    syntax = Syntax(diff_text, "diff", theme="monokai", line_numbers=True)
    console.print(Panel(syntax, title=f"Предлагаемые изменения в {file_path}"))

def main():
    console.print(Panel.fit("🤖 Добро пожаловать в AgentOrchestrator! 🤖", style="bold green"))
    
    # 1. Проверяем API-ключ
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        console.print("[yellow]GEMINI_API_KEY не найден в переменных окружения или файле .env.[/yellow]")
        api_key = Prompt.ask("Введите ваш Gemini API Key")
        if not api_key:
            console.print("[red]Ключ API обязателен для работы. Выход.[/red]")
            sys.exit(1)
        # Записываем в .env для будущего использования
        with open(".env", "a") as f:
            f.write(f"\nGEMINI_API_KEY={api_key}\n")
            
    # Инициализируем клиент Gemini
    client = genai.Client(api_key=api_key)
    
    # Задаем родительскую папку проекта (на уровень выше, так как скрипт лежит в подпапке)
    project_root = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))
    
    # 2. Инициализируем агентов
    designer = DesignerAgent(client)
    planner = PlannerAgent(client)
    coder = CoderAgent(client)
    verifier = VerifierAgent(client)
    reminder_agent = RussianReminderAgent(client)
    
    # Запускаем Агента-Русификатора для напоминания
    with console.status("[bold red]Агент-Русификатор проверяет языковые настройки...[/bold red]"):
        reminder_msg = reminder_agent.remind()
    console.print(Panel(reminder_msg, title="📢 Агент-Русификатор", border_style="red"))

    
    # 3. Запрашиваем задачу у пользователя
    task = Prompt.ask("[bold blue]Какую задачу вы хотите решить?[/bold blue]")
    if not task:
        console.print("[red]Задача не может быть пустой. Выход.[/red]")
        sys.exit(0)
        
    # 4. Проверяем, нужен ли Агент-Дизайнер
    run_designer = Confirm.ask("Хотите запустить Агента-Дизайнера для разработки UI/UX стиля?")
    design_guide = None
    if run_designer:
        with console.status("[bold purple]Агент-Дизайнер ищет идеи оформления в интернете...[/bold purple]"):
            design_guide = designer.propose_design(task)
        console.print(Panel(Markdown(design_guide), title="Руководство по стилю (Style Guide)"))
        
        # Сохраняем в файл для истории
        with open(os.path.join(project_root, "style_guide.md"), "w", encoding="utf-8") as f:
            f.write(design_guide)
        console.print("[green]Дизайн-документ сохранен в style_guide.md[/green]\n")
        
    # 5. Сканируем файлы проекта
    files = get_workspace_files(project_root)
    
    # 6. Агент-Планировщик строит план действий
    with console.status("[bold yellow]Агент-Планировщик анализирует проект и строит план...[/bold yellow]"):
        plan = planner.plan_task(task, files, design_guide)
        
    console.print(Panel(Markdown(plan), title="План изменений"))
    
    proceed = Confirm.ask("Приступить к выполнению плана?")
    if not proceed:
        console.print("[yellow]Выполнение отменено.[/yellow]")
        sys.exit(0)
        
    # 7. Выполнение плана шаг за шагом
    # Извлекаем шаги из плана (простой парсинг пунктов списка)
    steps = [line.strip() for line in plan.split('\n') if line.strip().startswith("-") or line.strip().startswith("*") or re.match(r"^\d+\.", line.strip())]
    if not steps:
        # Если не распарсилось списком, возьмем весь текст плана как один шаг
        steps = [plan]
        
    for i, step in enumerate(steps, 1):
        console.print(f"\n[bold green]=== Шаг {i}/{len(steps)}: {step} ===[/bold green]")
        
        # Запрашиваем у пользователя, какой файл будем менять на этом шаге
        file_to_change = Prompt.ask("Какой файл изменить для этого шага? (или 'skip' для пропуска)")
        if file_to_change.lower() == 'skip':
            continue
            
        full_file_path = os.path.join(project_root, file_to_change)
        
        # Читаем исходное содержимое
        original_content = ""
        if os.path.exists(full_file_path):
            with open(full_file_path, "r", encoding="utf-8") as f:
                original_content = f.read()
        else:
            console.print(f"[yellow]Файл {file_to_change} будет создан.[/yellow]")
            
        # Агент-Кодер пишет изменения
        with console.status(f"[bold cyan]Агент-Кодер пишет код для {file_to_change}...[/bold cyan]"):
            diff_blocks = coder.modify_code(file_to_change, original_content, step)
            
        # Применяем изменения в памяти
        modified_content, parse_ok = apply_diff_blocks(file_to_change, original_content, diff_blocks)
        
        if not parse_ok:
            console.print("[red]Не удалось применить изменения автоматически. Попробуем еще раз?[/red]")
            retry = Confirm.ask("Запустить повторную генерацию кода?")
            if retry:
                # Повторная попытка с подсказкой об ошибке
                with console.status(f"[bold cyan]Повторная генерация кода для {file_to_change}...[/bold cyan]"):
                    diff_blocks = coder.modify_code(file_to_change, original_content, f"{step}\nОШИБКА: Предыдущая генерация не соответствовала SEARCH/REPLACE формату.")
                modified_content, parse_ok = apply_diff_blocks(file_to_change, original_content, diff_blocks)
                
        if parse_ok:
            # Показываем diff
            display_diff(file_to_change, original_content, modified_content)
            
            # Спрашиваем подтверждение
            write_approved = Confirm.ask(f"[bold green]Записать изменения в {file_to_change}?[/bold green]")
            if write_approved:
                # Создаем папки при необходимости
                os.makedirs(os.path.dirname(full_file_path), exist_ok=True)
                with open(full_file_path, "w", encoding="utf-8") as f:
                    f.write(modified_content)
                console.print(f"[green]Файл {file_to_change} сохранен.[/green]")
                
                # 8. Верификация (если настроена)
                run_test = Confirm.ask("Запустить проверку сборки/тестов?")
                if run_test:
                    cmd = Prompt.ask("Введите команду для сборки/теста (например, 'xcodebuild' или 'swift build')", default="git diff")
                    
                    with console.status("[bold magenta]Запуск верификации...[/bold magenta]"):
                        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=project_root)
                        
                    verification_report = verifier.verify(result.stdout + "\n" + result.stderr, result.returncode)
                    
                    if verification_report == "SUCCESS":
                        console.print("[green]Проверка пройдена успешно![/green]")
                    else:
                        console.print(Panel(verification_report, title="Отчет об ошибках тестировщика", style="red"))
            else:
                console.print("[yellow]Изменения сброшены.[/yellow]")
        else:
            console.print("[red]Шаг пропущен из-за ошибок парсинга.[/red]")

    console.print("\n[bold green]🎉 Все шаги плана обработаны! Работа завершена. 🎉[/bold green]")

if __name__ == "__main__":
    main()
