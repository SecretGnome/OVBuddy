#!/usr/bin/env python3
"""
Test script to verify templates and static files are correctly set up.
This version doesn't require hardware dependencies.
"""

import os
import sys

def test_file_structure():
    """Test that all required files exist"""
    print("Testing file structure...")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    required_files = {
        'templates/index.html': 'HTML template',
        'static/css/terminal.css': 'Terminal CSS theme',
        'static/js/app.js': 'JavaScript application',
    }
    
    all_good = True
    for rel_path, description in required_files.items():
        full_path = os.path.join(script_dir, rel_path)
        if os.path.exists(full_path):
            size = os.path.getsize(full_path)
            print(f"  ✓ {rel_path} ({size} bytes) - {description}")
        else:
            print(f"  ✗ {rel_path} - NOT FOUND")
            all_good = False
    
    return all_good

def test_html_template():
    """Test that HTML template is valid"""
    print("\nTesting HTML template...")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_path = os.path.join(script_dir, 'templates', 'index.html')
    
    try:
        with open(template_path, 'r') as f:
            content = f.read()
        
        # Check for essential elements
        checks = {
            '<!DOCTYPE html>': 'HTML5 doctype',
            '<html': 'HTML tag',
            '</html>': 'Closing HTML tag',
            'terminal': 'Terminal theme elements',
            '/static/css/terminal.css': 'CSS link',
            '/static/js/app.js': 'JavaScript link',
            'configForm': 'Configuration form',
            'wifiSection': 'WiFi section',
            'servicesSection': 'Services section',
        }
        
        all_good = True
        for check, description in checks.items():
            if check in content:
                print(f"  ✓ Found {description}")
            else:
                print(f"  ✗ Missing {description}")
                all_good = False
        
        return all_good
    except Exception as e:
        print(f"  ✗ Error reading template: {e}")
        return False

def test_css():
    """Test that CSS file contains terminal theme"""
    print("\nTesting CSS theme...")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    css_path = os.path.join(script_dir, 'static', 'css', 'terminal.css')
    
    try:
        with open(css_path, 'r') as f:
            content = f.read()
        
        # Check for terminal theme elements
        checks = {
            '--bg-primary': 'Background color variable',
            '--text-primary': 'Text color variable',
            '--border-color': 'Border color variable',
            'terminal-window': 'Terminal window class',
            'terminal-header': 'Terminal header class',
            '@keyframes': 'CSS animations',
            'monospace': 'Monospace font',
        }
        
        all_good = True
        for check, description in checks.items():
            if check in content:
                print(f"  ✓ Found {description}")
            else:
                print(f"  ✗ Missing {description}")
                all_good = False
        
        return all_good
    except Exception as e:
        print(f"  ✗ Error reading CSS: {e}")
        return False

def test_javascript():
    """Test that JavaScript file contains required functions"""
    print("\nTesting JavaScript...")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    js_path = os.path.join(script_dir, 'static', 'js', 'app.js')
    
    try:
        with open(js_path, 'r') as f:
            content = f.read()
        
        # Check for required functions
        checks = {
            'loadConfiguration': 'Load configuration function',
            'saveConfiguration': 'Save configuration function',
            'refreshWifiStatus': 'WiFi status function',
            'scanNetworks': 'Network scan function',
            'connectToNetwork': 'WiFi connect function',
            'refreshServicesStatus': 'Service status function',
            'controlService': 'Service control function',
            'showMessage': 'Message display function',
            '/api/config': 'API endpoint reference',
            '/api/wifi/': 'WiFi API reference',
            '/api/services/': 'Services API reference',
        }
        
        all_good = True
        for check, description in checks.items():
            if check in content:
                print(f"  ✓ Found {description}")
            else:
                print(f"  ✗ Missing {description}")
                all_good = False
        
        return all_good
    except Exception as e:
        print(f"  ✗ Error reading JavaScript: {e}")
        return False

def test_flask_imports():
    """Test that Flask can be imported"""
    print("\nTesting Flask availability...")
    
    try:
        from flask import Flask, render_template
        print("  ✓ Flask is installed")
        print("  ✓ render_template is available")
        return True
    except ImportError as e:
        print(f"  ✗ Flask not available: {e}")
        print("  Install with: pip3 install flask")
        return False

def main():
    print("="*60)
    print("OVBuddy Web Interface - Template Test")
    print("="*60)
    
    results = []
    
    results.append(("File Structure", test_file_structure()))
    results.append(("HTML Template", test_html_template()))
    results.append(("CSS Theme", test_css()))
    results.append(("JavaScript", test_javascript()))
    results.append(("Flask", test_flask_imports()))
    
    print("\n" + "="*60)
    print("Test Results Summary")
    print("="*60)
    
    all_passed = True
    for test_name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"  {status} - {test_name}")
        if not passed:
            all_passed = False
    
    print("="*60)
    
    if all_passed:
        print("\n🎉 All tests passed!")
        print("\nThe web interface template system is correctly set up.")
        print("\nNext steps:")
        print("  1. Deploy to Raspberry Pi: ./scripts/deploy.sh")
        print("  2. Test on device: python3 ovbuddy_web.py")
        print("  3. Access at: http://ovbuddy.local:8080")
        return 0
    else:
        print("\n❌ Some tests failed!")
        print("\nPlease fix the issues above before deploying.")
        return 1

if __name__ == '__main__':
    sys.exit(main())

