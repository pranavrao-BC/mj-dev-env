#!/usr/bin/env nu
use ../lib *

def "main save" [name: string] {
  save-snapshot $name
}

def "main restore" [name: string] {
  restore-snapshot $name
}

def "main list" [] {
  list-snapshots
}

def "main delete" [name: string] {
  delete-snapshot $name
}

def main [] {
  main list
}
