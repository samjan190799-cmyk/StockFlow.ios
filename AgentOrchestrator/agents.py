import os
import re
from google import genai
from google.genai import types

class Agent:
    def __init__(self, client: genai.Client, model: str = "gemini-3.5-flash"):
        self.client = client
        self.model = model

class DesignerAgent(Agent):
    """
    Агент-Дизайнер: Исследует тренды дизайна в интернете и предлагает палитры, шрифты,
    элементы интерфейса и лучшие UX-практики.
    """
    def propose_design(self, app_theme: str) -> str:
        prompt = f"""
        Ты - эксперт по UI/UX дизайну мобильных приложений (особенно iOS/SwiftUI).
        Твоя задача - изучить современные тенденции дизайна для следующей темы: "{app_theme}".
        Используй веб-поиск, чтобы найти популярные стили, палитры цветов, UX паттерны (например, на Dribbble, Behance, Apple Human Interface Guidelines).
        
        Составь подробное руководство по стилю (Style Guide) в формате Markdown, содержащее:
        1. Идею и концепцию дизайна (например, неоморфизм, стеклянный дизайн, минимализм).
        2. Цветовую палитру: HEX-коды для основного (Primary), фонового (Background), акцентного (Accent) цветов и градиентов.
        3. Типографику (шрифты, размеры, начертания).
        4. Макет ключевых экранов (UX Wireframe) с описанием расположения элементов.
        5. Примеры микро-анимаций для улучшения вовлеченности.
        
        Пиши на русском языке. Будь конкретен, предлагай только современные и эстетичные решения.
        """
        
        # Используем Google Search Grounding для поиска свежих трендов в сети
        response = self.client.models.generate_content(
            model=self.model,
            contents=prompt,
            config=types.GenerateContentConfig(
                tools=[{"google_search": {}}],
            )
        )
        return response.text

class PlannerAgent(Agent):
    """
    Агент-Планировщик: Получает задачу пользователя, рекомендации дизайнера,
    список файлов проекта и строит пошаговый план изменений.
    """
    def plan_task(self, task: str, files_list: list[str], design_guide: str = None) -> str:
        design_context = f"\nРекомендации дизайнера по стилю:\n{design_guide}\n" if design_guide else ""
        
        prompt = f"""
        Ты - системный архитектор и ведущий разработчик ПО.
        Твоя задача - разработать пошаговый план выполнения задачи.
        
        Задача: "{task}"
        {design_context}
        Доступные файлы проекта:
        {", ".join(files_list)}
        
        Напиши пошаговый план реализации в формате Markdown.
        Для каждого шага укажи:
        1. Какой конкретно файл нужно создать или изменить.
        2. Что именно должно быть сделано (логика, UI элементы).
        3. Зависимости (какие файлы менять сначала, какие потом).
        
        План должен быть максимально детальным, чтобы разработчик мог писать код по каждому шагу изолированно.
        """
        
        response = self.client.models.generate_content(
            model=self.model,
            contents=prompt
        )
        return response.text

class CoderAgent(Agent):
    """
    Агент-Разработчик: Читает файл, шаг плана и выдает изменения в формате SEARCH/REPLACE блоков.
    """
    def modify_code(self, file_path: str, file_content: str, step_description: str) -> str:
        prompt = f"""
        Ты - опытный разработчик. Тебе нужно внести изменения в файл {file_path} на основе инструкции.
        
        Инструкция к изменению:
        {step_description}
        
        Полное текущее содержимое файла {file_path}:
        ```swift
        {file_content}
        ```
        
        Выведи изменения строго в формате блоков SEARCH/REPLACE.
        Каждое изменение должно быть оформлено следующим образом:
        
        <<<<<<< SEARCH
        [точные строки из оригинального файла, которые нужно заменить]
        =======
        [новые строки, которые заменят SEARCH-блок]
        >>>>>>> REPLACE
        
        Правила:
        1. В блоке SEARCH пиши строки в точности так, как они написаны в файле (включая все пробелы и табы).
        2. Делай блоки SEARCH достаточно большими и уникальными, чтобы их можно было однозначно найти в файле.
        3. Если нужно вставить новый код в определенное место, укажи строки до и после места вставки в SEARCH-блоке, а в REPLACE-блоке вставь новый код между ними.
        4. Если файл новый и пустой, то блок SEARCH будет пустым:
        <<<<<<< SEARCH
        =======
        [содержимое нового файла]
        >>>>>>> REPLACE
        
        Выдавай только эти блоки, без лишних слов, комментариев и форматирования markdown.
        """
        
        response = self.client.models.generate_content(
            model=self.model,
            contents=prompt
        )
        return response.text

class VerifierAgent(Agent):
    """
    Агент-Тестировщик/Валидатор: Анализирует вывод тестов/компиляции и предлагает исправления в случае ошибок.
    """
    def verify(self, command_output: str, exit_code: int) -> str:
        if exit_code == 0:
            return "SUCCESS"
            
        prompt = f"""
        Команда сборки или запуска тестов завершилась с ошибкой (код выхода {exit_code}).
        
        Вывод терминала:
        {command_output}
        
        Проанализируй ошибку. Объясни простым языком, почему она возникла и какие файлы/строки нужно исправить, чтобы решить проблему.
        """
        
        response = self.client.models.generate_content(
            model=self.model,
            contents=prompt
        )
        return response.text

class RussianReminderAgent(Agent):
    """
    Агент-Русификатор (Russian Reminder Agent): Напоминает, что всё общение, документация,
    комментарии и описания должны быть строго на русском языке.
    """
    def remind(self) -> str:
        prompt = """
        Сгенерируй вежливое, но очень настойчивое напоминание на русском языке о том, что абсолютно всё общение,
        планы, комментарии к коду, документация и задачи должны вестись строго на русском языке.
        Используй яркие эмодзи (например, 🇷🇺, 🤖, ⚠️) и сделай напоминание запоминающимся.
        """
        response = self.client.models.generate_content(
            model=self.model,
            contents=prompt
        )
        return response.text

class NetworkDebuggerAgent(Agent):
    """
    Агент-Сетевой Диагност (Network Debugger Agent): Выполняет анализ
    подключения к серверам FTP/FTPS/SFTP и генерирует отчет о сетевых проблемах.
    """
    def diagnose(self, host: str, port: int, error_message: str) -> str:
        prompt = f"""
        Пользователь столкнулся с ошибкой подключения к серверу {host}:{port}.
        Сообщение об ошибке: "{error_message}"
        
        Твоя задача:
        1. Проанализировать ошибку (например, таймаут чтения баннера, ошибка сокета, сбой TLS).
        2. Объяснить на русском языке простыми словами возможные причины (блокировка провайдером, настройки фаервола на iOS, некорректная обработка буфера сокета).
        3. Предложить пошаговые рекомендации по решению проблемы на клиенте (в коде Swift) и на сервере/сети.
        
        Напиши подробный отчет в формате Markdown на русском языке.
        """
        response = self.client.models.generate_content(
            model=self.model,
            contents=prompt
        )
        return response.text


