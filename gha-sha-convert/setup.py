from setuptools import setup, find_packages

setup(
    name="gha-sha-convert",
    version="1.0.0",
    description="Pre-commit hook to convert GitHub Actions to SHA-pinned versions",
    author="Alfresco Build Tools",
    packages=find_packages(),
    python_requires=">=3.6",
    install_requires=[
        "requests>=2.25.0",
    ],
    entry_points={
        "console_scripts": [
            "gha-sha-convert=gha_sha_convert:main",
        ],
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.6",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
)
